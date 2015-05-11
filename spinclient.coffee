angular.module('ngSpinclient', ['uuid4', 'ngMaterial']).factory 'spinclient', (uuid4, $q) ->
  #public methods & properties
  service = {

    subscribers         : []
    objsubscribers      : []
    outstandingMessages : []
    modelcache          : []

    #io                  : io('ws://localhost:3003')
    io                  : io('ws://quantifiedplanet.org:1009')

    registerListener: (detail) ->
      subscribers = service.subscribers[detail.message] or []
      subscribers.push detail.callback
      service.subscribers[detail.message] = subscribers

    registerObjectSubscriber: (detail) ->
      d = $q.defer()
      #.log 'message-router registering subscriber for object ' + detail.id + ' type ' + detail.type
      subscribers = service.objsubscribers[detail.id] or []
      service.emitMessage(
        target: 'registerForUpdatesOn'
        messageId: uuid4.generate()
        obj: {id: detail.id, type: detail.type}).then (reply) ->
          subscribers[reply] = detail.cb
          service.objsubscribers[detail.id] = subscribers
          d.resolve(reply)
      return d.promise

    deRegisterObjectSubscriber: (sid, o) =>
      subscribers = service.objsubscribers[o.id] or []
      if subscribers and subscribers[sid]
        delete subscribers[sid]
        service.objsubscribers[o.id] = subscribers
        service.emitMessage( { target: 'deRegisterForUpdatesOn', id:o.id, type: o.type, listenerid: sid } ).then (reply) ->

    emitMessage : (detail) ->
      #console.log 'emitMessage called'
      #console.dir detail
      d = $q.defer()
      detail.messageId = uuid4.generate()
      service.outstandingMessages.push detail
      service.io.emit 'message', JSON.stringify(detail)
      detail.d = d
      return d.promise

    # ------------------------------------------------------------------------------------------------------------------

    getModelFor: (type) ->
      d = $q.defer()
      if service.modelcache[type]
        d.resolve(service.modelcache[type])
      else
        service.emitMessage({target:'getModelFor', modelname: type}).then((model)->
          service.modelcache[type] = model
          d.resolve(model))
      return d.promise

    listTargets: () ->
      d = $q.defer()
      service.emitMessage({target:'listcommands'}).then((targets)-> d.resolve(targets))
      return d.promise

    flattenModel: (model) ->
      rv = {}
      for k,v of model
        if angular.isArray(v)
          rv[k] = v.map (e) -> e.id
        else
          rv[k] = v
      return rv
  }



  service.subscribers['OBJECT_UPDATE'] = [ (obj) ->
    console.log '+++++++++++ obj update message router got obj'
    #console.dir(obj);
    subscribers = service.objsubscribers[obj.id] or []
    #if subscribers.length == 0
    #  console.log '* OH NOES! * No subscribers for object update on object ' + obj.id
    #  console.dir service.objsubscribers
    #else
    #  subscribers.forEach (subscriber) ->
    #    subscriber obj
    for k,v of subscribers
      #console.log k+' -> '+v
      v obj
  ]

  #service.io.onMessage (reply) ->
  service.io.on 'message', (reply) ->
    status = reply.status
    message = reply.payload
    info = reply.info
    #console.log 'got reply id ' + reply.messageId + ' status ' + status + ', info ' + info + ' data ' + message
    #console.dir reply
    index = -1
    if reply.messageId
      i = 0
      while i < service.outstandingMessages.length
        detail = service.outstandingMessages[i]
        if detail.messageId == reply.messageId
          if reply.status == 'FAILURE'
            detail.d.reject reply
          else
            detail.d.resolve message
            index = i
            break
        i++
      if index > 0
        service.outstandingMessages.splice index, 1
    else
      subscribers = service.subscribers[info]
      if subscribers
        subscribers.forEach (listener) ->
          #console.log("sending reply to listener");
          listener message
          return
      else
        console.log 'no subscribers for message ' + message
        console.dir reply
    return
  return service

  #---------------------------------------------------------------------------------

.directive 'alltargets', [
  'spinclient'
  (client) ->
    {
    restrict: 'AE'
    replace: true
    #templateUrl: 'alltargets.html'
    template:'<div>
    <h2>Status: {{status}}</h2>
    Return Type:<md-select ng-model="currentmodeltype" placeholder="Select a return type for calls">
        <md-option ng-value="opt" ng-repeat="opt in modeltypes">{{ opt }}</md-option>
    </md-select>
    <div layout="row">
        <div flex>
            <div ng-repeat="target in targets">
                <button ng-click="callTarget(target)">{{target.name}}</button> - <span ng-if="target.args==\'<none>\'">{{target.args}}</span><span ng-if="target.args!=\'<none>\'"><input type="text" ng-model="target.args"></span>
            </div>
        </div>
        <div flex>
            <spinlist ng-if="results && results.length > 0" list="results" listmodel="currentmodeltype" edit="\'true\'" onselect="onitemselect" style="height:300px;overflow:auto"></spinlist>
            <md-divider></md-divider>
            <div ng-if="itemselected">
                <spinwalker model="itemselected" edit="\'true\'"></spinwalker>
            </div>
        </div>
    </div>
</div>'
    link: (scope, elem, attrs) ->

    controller: ($scope) ->
      $scope.results = []
      console.log 'alltargets controller'

      $scope.onitemselect = (item) =>
        console.log 'alltargets item selected '+item.name
        $scope.itemselected = item

      client.listTargets().then (_targets) ->
        $scope.targets = []
        for k,v of _targets
          $scope.targets.push {name:k, argnames: v, args:v}

      success = (results)->
        $scope.results = results
        console.dir($scope.results)

      failure = (reply) ->
        console.log 'failure'+reply
        $scope.status = reply.status + ' - ' +reply.info

      $scope.callTarget = (t) ->
        $scope.status = "";
        console.log 'calltarget called with '+t.name
        callobj = {target:t.name}
        if t.argnames != "<none>"
          values = t.args.split(',')
          i = 0
          t.argnames.split(',').forEach (arg) ->
            callobj[arg] = values[i++]
        client.emitMessage(callobj).then(success,failure)

      client.emitMessage({target:'listTypes'}).then (types)-> $scope.modeltypes = types

    }
  ]
.directive 'spinmodel', [
  'spinclient'
  (client) ->
    {
    restrict:    'AE'
    replace:     true
    #templateUrl: 'spinmodel.html'
    template:'<div>
    <md-list >
        <md-subheader class="md-no-sticky" style="background-color:#ddd">
            <md-icon md-svg-src="images/ic_folder_shared_24px.svg" ></md-icon>
            SpinCycle Model {{model.type}}</md-subheader>
        <md-list-item ng-repeat="prop in listprops" >
            <div class="md-list-item-text" layout="row">
                <div flex style="background-color:#eee;margin-bottom:2px"> {{prop.name}} </div>
                <span flex ng-if="prop.type && prop.value && !prop.hashtable">
                    <md-button ng-click="enterDirectReference(prop)">{{prop.name}}</md-button> >
                </span>
                <div ng-if="!prop.array && !prop.type" flex class="md-secondary">
                    <span ng-if="edit && prop.name != \'id\'"><input type="text" ng-model="model[prop.name]" ng-change="onChange(model, prop.name)"></span>
                    <span ng-if="!edit || prop.name == \'id\'">{{prop.value}}</span>
    </div>
                <div flex ng-if="edit && prop.array">
                    <div><md-button class="md-raised" ng-click="addModel(prop.type, prop.name)">New {{prop.type}}</md-button></div>
                    <spinlist  flex class="md-secondary" listmodel="prop.type" edit="edit" list="prop.value" onselect="onselect" ondelete="ondelete"></spinlist>
    </div>
                <span flex ng-if="!edit && prop.array">
                    <spinlist flex class="md-secondary" listmodel="prop.name" list="prop.value" onselect="onselect"></spinlist>
    </span>
                <div flex ng-if="prop.hashtable">
                    <div ng-if="edit"><md-button class="md-raised" ng-click="addModel(prop.type, prop.name)">New {{prop.type}}</md-button></div>
                    <spinhash flex class="md-secondary" listmodel="prop.type" list="prop.value" onselect="onselect"></spinhash>
    </div>
            </div>
    </md-list-item>
    </md-list>
</div>'
    scope:
      model: '=model'
      edit: '=edit'
      onselect: '&'

    link:        (scope, elem, attrs) ->
      scope.onselect = scope.onselect()

    controller:  ($scope) ->
      #console.log 'spinmodel got model'
      #console.dir $scope.model

      $scope.isarray = angular.isArray
      $scope.subscriptions = []

      $scope.onSubscribedObject = (o) ->
        $scope.model = o

      if($scope.model)
        client.registerObjectSubscriber({ id: $scope.model.id, type: $scope.model.type, cb: $scope.onSubscribedObject}).then (listenerid) ->
          $scope.subscriptions.push {sid: listenerid, o: $scope.model}

      $scope.$watch 'model', (newval, oldval) ->
        console.log 'spinmodel watch fired for '+newval.name
        #console.log 'edit is '+$scope.edit
        $scope.renderModel()

      success = (result) =>
        console.log 'success: '+result

      failure = (err) =>
        console.log 'error: '+err

      $scope.onChange = (model,prop) =>
        console.log 'onChange called for'
        console.dir model
        #console.dir prop
        client.emitMessage({target:'updateObject', obj: model}).then(success, failure)

      $scope.ondelete = (item) ->
        #console.log 'model delete for list item'
        # get property name for item type
        client.getModelFor($scope.model.type).then (md) ->
          propname = null
          md.forEach (m) -> propname = m.name if m.type == item.type
          # get the list and splice out the deleted item
          list = $scope.model[propname]
          for mid,i in list
            if mid == item.id
              list.splice i,1
          # update this model
          console.log 'updating parent model to list with spliced list'
          client.emitMessage({target:'updateObject', obj: $scope.model}).then( ()->
            # actually delete the model formerly in the list
            client.emitMessage( {target:'_delete'+item.type, obj: {id:mid, type:item.type}}).then (o)=>
              console.log 'deleted '+item.type+' on server'
          , failure)

      $scope.renderModel = () =>
        console.log 'spinmodel::renderModel called for '+$scope.model.name
        console.dir $scope.model
        $scope.listprops = []
        client.getModelFor($scope.model.type).then (md) ->
          modeldef = {}
          md.forEach (modelprop) -> modeldef[modelprop.name] = modelprop
          if $scope.model
            console.log 'making listprops for model'
            console.dir md
            $scope.listprops.push {name: 'id', value: $scope.model.id}
            #delete $scope.model.id
            for prop,i in md
              if(prop.name != 'id')
                foo = {name: prop.name, value: $scope.model[prop.name] || "", type: modeldef[prop.name].type, array:modeldef[prop.name].array, hashtable:modeldef[prop.name].hashtable}
                $scope.listprops.push foo

      $scope.enterDirectReference = (prop) =>
        console.log 'enterDirectReference called for '
        console.dir prop
        client.emitMessage({ target:'_get'+prop.type, obj: {id: $scope.model[prop.name], type: prop.type }}).then( (o)->
          console.log 'enterDirectReference got back '
          console.dir o
          $scope.onselect(o)
        , failure)

      $scope.addModel = (type, propname) ->
        console.log 'addModel called for type '+type
        client.emitMessage({target:'_create'+type, obj: {name: 'new '+type, type:type}}).then((o)=>
          #console.log 'addModel for '+type+' got back object id for new instance = '+o.id
          $scope.model[propname].push(o.id)
          console.log 'parent model is now'
          console.dir $scope.model
          client.emitMessage({target:'updateObject', obj: $scope.model}).then(success, failure)
        , failure)

      $scope.$on '$destroy', () =>
        console.log 'spinmodel captured $destroy event'
        $scope.subscriptions.forEach (s) =>
          client.deRegisterObjectSubscriber(s.sid, s.o)

    }
  ]
.directive 'spinwalker', [
  'spinclient'
  (client) ->
    {
    restrict: 'AE'
    replace: true
    #templateUrl: 'spinwalker.html
    template:'<div>
    <span ng-repeat="crumb in breadcrumbs">
       <md-button ng-click="crumbClicked(crumb)">{{crumbPresentation(crumb)}}</md-button> >
    </span>
    <md-divider></md-divider>
    <spinmodel model="selectedmodel" edit="edit" onselect="onselect" style="height:400px;overflow:auto"></spinmodel>
</div>'
    scope:
      model: '=model'
      edit: '=edit'

    link: (scope, elem, attrs) ->

    controller: ($scope) ->
      $scope.selectedmodel = $scope.model
      $scope.breadcrumbs = [$scope.model]

      $scope.$watch 'model', (newval, oldval) ->
        $scope.breadcrumbs = [$scope.model]
        $scope.selectedmodel = newval

      $scope.crumbClicked = (model) ->
        $scope.selectedmodel = model
        idx = -1
        for crumb, i  in $scope.breadcrumbs
          idx = i if crumb.id = model.id
        console.log 'crumbClicked crumbs length = '+$scope.breadcrumbs.length
        if idx > -1 and $scope.breadcrumbs.length > 1
          $scope.breadcrumbs.splice idx,1

      $scope.onselect = (model, replace) ->
        console.log 'spinwalker onselect for model '+model.name
        console.log model
        $scope.breadcrumbs = [] if replace
        $scope.selectedmodel = model
        $scope.breadcrumbs.push model

      $scope.crumbPresentation = (crumb) =>
        crumb.name || crumb.type

    }
  ]
.directive 'spinlist', [
  'spinclient'
  (client) ->
    {
    restrict:    'AE'
    replace:     true
    #templateUrl: 'spinlist.html'
    template:'<div>
    <md-list >
        <md-subheader class="md-no-sticky" style="background-color:#ddd">
            <md-icon md-svg-src="images/ic_apps_24px.svg" ></md-icon>
                SpinCycle List of {{listmodel}}s</md-subheader>
        <md-list-item ng-repeat="item in expandedlist" >
            <div class="md-list-item-text" layout="row">
                <span flex >
                    <md-button ng-if="!edit" aria-label="delete" class="md-icon-button" ng-click="deleteItem(item)">
                        <md-icon md-svg-src="images/ic_delete_24px.svg"></md-icon>
                    </md-button> <md-button  ng-click="selectItem(item, true)">{{ item.name }}</md-button>
                </span>
                <!-- <span flex class="md-secondary"> {{item.id}}</span> -->
            </div>
        </md-list-item>
    </md-list>
</div>'
    scope:
      list: '=list'
      listmodel: '=listmodel'
      onselect: '&'
      ondelete: '&'

    link:        (scope, elem, attrs) ->
      scope.onselect = scope.onselect()
      scope.ondelete = scope.ondelete()

    controller:  ($scope) ->
      console.log 'spinlist created. list is '+$scope.list.length+' items, type is '+$scope.listmodel
      $scope.subscriptions = []
      $scope.objects = []
      $scope.expandedlist = []

      success = (result) =>
        console.log 'success: '+result

      failure = (err) =>
        console.log 'error: '+err
        console.dir err

      $scope.selectItem = (item, replace) =>
        #console.log 'item '+item.name+' selected'
        $scope.onselect(item, replace) if $scope.onselect

      $scope.deleteItem = (item) ->
        #console.log 'list delete'
        $scope.ondelete(item) if $scope.ondelete


      for model in $scope.list
        client.emitMessage({ target:'_get'+$scope.listmodel, obj: {id: model.id, type: $scope.listmodel }}).then( (o)->
          for mod,i in $scope.list
            if mod.id == o.id
              #console.log '-- exhanging list id with actual list model from server for '+o.name
              $scope.expandedlist[i] = o
        , failure)

      $scope.onSubscribedObject = (o) ->
        console.log 'onSubscribedObject called ++++++++++++++++++++++++'
        console.dir(o)
        added = false
        for model,i in $scope.list
          if model.id == o.id
            console.log 'found match in update for object '+o.id+' name '+o.name
            mod = $scope.expandedlist[i]
            for k,v of o
              added = true
              mod[k] = v
        if not added
          $scope.expandedlist.push(o)
        $scope.$apply()

      #console.log 'subscribing to list ids..'
      $scope.list.forEach (model) ->
        if model.id
          client.registerObjectSubscriber(
            id: model.id
            type: $scope.listmodel
            cb: $scope.onSubscribedObject
          ).then (listenerid) ->
            $scope.subscriptions.push {sid: listenerid, o: {type:$scope.listmodel, id: model.id}}

      $scope.$on '$destroy', () =>
        console.log 'spinlist captured $destroy event'
        $scope.subscriptions.forEach (s) =>
          client.deRegisterObjectSubscriber(s.sid,s.o)
    }
  ]
.directive 'spinhash', [
  'spinclient'
  (client) ->
    {
    restrict:    'AE'
    replace:     true
    templateUrl: 'spinhash.html'
    scope:
      list: '=list'
      listmodel:   '=listmodel'
      onselect:    '&'
      ondelete:    '&'

    link: (scope, elem, attrs) ->
      scope.onselect = scope.onselect()
      #scope.ondelete = scope.ondelete()

    controller: ($scope) ->
      console.log 'spinhash list for model '+$scope.listmodel+' is'
      console.dir $scope.list

      $scope.expandedlist = []

      failure = (err) =>
        console.log 'error: '+err
        console.dir err

      for mid in $scope.list
        client.emitMessage({ target:'_get'+$scope.listmodel, obj: {id: mid, type: $scope.listmodel }}).then( (o)->
          for modid,i in $scope.list
            if modid == o.id
              console.log 'adding hashtable element '+o.name
              $scope.expandedlist[i] = o
        , failure)

      $scope.selectItem = (item, replace) =>
        #console.log 'item '+item.name+' selected'
        $scope.onselect(item, replace) if $scope.onselect

    }
  ]
