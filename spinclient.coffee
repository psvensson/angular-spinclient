angular.module('ngSpinclient', ['uuid4', 'ngMaterial']).factory 'spinclient', (uuid4, $q, $rootScope) ->
  #public methods & properties
  service = {

    subscribers         : []
    objsubscribers      : []
    objectsSubscribedTo : []

    outstandingMessages : []
    modelcache          : []
    rightscache          : []

    #io                  : io('ws://localhost:3003')
    io                  : null
    sessionId           : null
    objects             : []
    failureMessage      : undefined

    failed: (msg)->
      console.log 'spinclient message failed!! '+msg

    setSessionId: (id) ->
      if(id)
        console.log '++++++++++++++++++++++++++++++++++++++ spinclient setting session id to '+id
        service.sessionId = id

    dumpOutstanding: ()->
      #console.log '-------------------------------- '+service.outstandingMessages.length+' outstanding messages ---------------------------------'
      #service.outstandingMessages.forEach (os)->
      #  console.log os.messageId+' -> '+os.target+' - '+os.d
      #console.log '-----------------------------------------------------------------------------------------'

    setWebSocketInstance: (io) =>
      service.io = io

      service.io.on 'message', (reply) ->
        status = reply.status
        message = reply.payload
        info = reply.info
        #console.log 'got reply messageId ' + reply.messageId + ' status ' + status + ', info ' + info + ' data ' + message + ' outstandingMessages = '+service.outstandingMessages.length
        service.dumpOutstanding()
        #console.dir reply
        index = -1
        if reply.messageId
          i = 0
          while i < service.outstandingMessages.length
            detail = service.outstandingMessages[i]
            if detail.messageId == reply.messageId
              if reply.status == 'FAILURE'
                console.log 'spinclient message FAILURE'
                console.dir reply
                service.failuremessage = reply.info
                detail.d.reject reply
                break
              else
                #console.log 'delivering message '+message+' reply to '+detail.target+' to '+reply.messageId
                detail.d.resolve(message)
                index = i
                break
            i++
          if index > -1
            #console.log 'removing outstanding reply'
            service.outstandingMessages.splice index, 1
        else
          subscribers = service.subscribers[info]
          if subscribers
            subscribers.forEach (listener) ->
              #console.log("sending reply to listener");
              listener message
          else
            console.log 'no subscribers for message ' + message
            console.dir reply

    registerListener: (detail) ->
      console.log 'spinclient::registerListener called for '+detail.message
      subscribers = service.subscribers[detail.message] or []
      subscribers.push detail.callback
      service.subscribers[detail.message] = subscribers

    registerObjectSubscriber: (detail) ->
      d = $q.defer()
      sid = uuid4.generate()
      localsubs = service.objectsSubscribedTo[detail.id]
      console.log 'registerObjectSubscriber localsubs is'
      console.dir localsubs
      if not localsubs
        localsubs = []
        console.log 'no local subs, so get the original server-side subscription for id '+detail.id
        # actually set up subscription, once for each object
        service._registerObjectSubscriber({id: detail.id, type: detail.type, cb: (updatedobj) ->
          console.log '-- registerObjectSubscriber getting obj update callback for '+detail.id
          lsubs = service.objectsSubscribedTo[detail.id]
          #console.dir(lsubs)
          for k,v of lsubs
            if (v.cb)
              console.log '--*****--*****-- calling back object update to local sid --****--*****-- '+k
              v.cb updatedobj
        }).then (remotesid) ->
          localsubs['remotesid'] = remotesid
          localsubs[sid] = detail
          console.log '-- adding local callback listener to object updates for '+detail.id+' local sid = '+sid+' remotesid = '+remotesid
          service.objectsSubscribedTo[detail.id] = localsubs
          d.resolve(sid)
      return d.promise

    _registerObjectSubscriber: (detail) ->
      d = $q.defer()
      console.log 'message-router registering subscriber for object ' + detail.id + ' type ' + detail.type
      subscribers = service.objsubscribers[detail.id] or []

      service.emitMessage({target: 'registerForUpdatesOn', obj: {id: detail.id, type: detail.type} }).then(
        (reply)->
          console.log 'server subscription id for id '+detail.id+' is '+reply
          subscribers[reply] = detail.cb
          service.objsubscribers[detail.id] = subscribers
          d.resolve(reply)
        ,(reply)->
          service.failed(reply)
        )
      return d.promise

    deRegisterObjectSubscriber: (sid, o) =>
      localsubs = service.objectsSubscribedTo[o.id] or []
      if localsubs[sid]
        console.log 'deregistering local updates for object '+o.id
        delete localsubs[sid]
        count = 0
        for k,v in localsubs
          count++
        if count == 1 # only remotesid property left
          service._deRegisterObjectSubscriber('remotesid', o)

    _deRegisterObjectSubscriber: (sid, o) =>
      subscribers = service.objsubscribers[o.id] or []
      if subscribers and subscribers[sid]
        delete subscribers[sid]
        service.objsubscribers[o.id] = subscribers
        service.emitMessage({target: 'deRegisterForUpdatesOn', id:o.id, type: o.type, listenerid: sid } ).then (reply)->
          console.log 'deregistering server updates for object '+o.id

    emitMessage : (detail) ->
      #console.log 'emitMessage called'
      #console.dir detail
      d = $q.defer()
      detail.messageId = uuid4.generate()
      detail.sessionId = service.sessionId
      detail.d = d
      service.outstandingMessages.push detail
      #console.log 'saving outstanding reply to messageId '+detail.messageId+' and sessionId '+detail.sessionId
      service.io.emit 'message', JSON.stringify(detail)

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

    getRightsFor: (type) ->
      d = $q.defer()
      if service.rightscache[type]
        d.resolve(service.rightscache[type])
      else
        service.emitMessage({target:'getAccessTypesFor', modelname: type}).then((rights)->
          service.rightscache[type] = rights
          d.resolve(rights))
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
    #console.log 'spinclient +++++++++ obj update message router got obj'
    #console.dir(obj);
    subscribers = service.objsubscribers[obj.id] or []
    for k,v of subscribers
      #console.log 'updating subscriber to object updates on id '+k
      if not service.objects[obj.id]
        service.objects[obj.id] = obj
      else
        o = service.objects[obj.id]
        for prop, val of obj
          o[prop] = val
      v obj
  ]

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
  'spinclient', '$mdDialog'
  (client, $mdDialog) ->
    {
    restrict:    'AE'
    replace:     true
    #templateUrl: 'spinmodel.html'
    template:'<div>
    <md-subheader class="md-no-sticky" style="background-color:#ddd">
            <md-icon md-svg-src="assets/images/ic_folder_shared_24px.svg" ></md-icon>
            {{model.type}} {{objects[model.id].name}}</md-subheader>
    <md-list >

            <md-list-item ng-repeat="prop in listprops" layout-fill>
                    <md-input-container layout="row" layout-fill style="min-height:20px">
                      <label> {{prop.name}} </label>
                      <span flex ng-if="prop.type && prop.value && !prop.hashtable && !prop.array">
                          <md-button ng-click="enterDirectReference(prop)">{{prop.name}}</md-button> >
                      </span>
                      <input ng-if="!prop.array && !prop.type && isEditable(prop.name) && prop.name != \'id\'" type="text" ng-model="model[prop.name]" ng-change="onChange(model, prop.name)">
                      <input ng-if="!prop.array && !prop.type && !isEditable(prop.name) || prop.name == \'id\'" type="text" ng-model="model[prop.name]" disabled="true">

                      <div ng-if="accessrights[prop.type].create && (prop.array || prop.hashtable)"><md-button class="md-raised" ng-click="addModel(prop.type, prop.name)">New {{prop.type}}</md-button></div>
                      <div ng-if="accessrights[model.type].write && (prop.array || prop.hashtable)"><md-button class="md-raised" ng-click="selectModel(prop.type, prop.name)">Add {{prop.type}}</md-button></div>
                      <spinlist ng-if="isEditable(prop.name) && prop.array" flex  listmodel="prop.type" edit="edit" list="model[prop.name]" onselect="onselect" ondelete="ondelete"></spinlist>
                      <spinlist ng-if="!isEditable(prop.name) && prop.array" flex  listmodel="prop.type" list="model[prop.name]" onselect="onselect"></spinlist>
                      <spinhash ng-if="prop.hashtable" flex  listmodel="prop.type" list="prop.value" onselect="onselect"></spinhash>
                    </md-input-container>
        </md-list-item>
    </md-list>
</div>'
    scope:
      model: '=model'
      edit: '=?edit'
      onselect: '&'
      hideproperties: '=?hideproperties'

    link:        (scope) ->
      scope.onselect = scope.onselect()

    controller:  ($scope) ->
      $scope.hideproperties = $scope.hideproperties or []
      #console.log 'spinmodel got model '+$scope.model+' hideproperties are '+$scope.hideproperties
      #console.dir $scope.hideproperties
      #console.dir $scope.model

      $scope.isarray = angular.isArray
      $scope.subscription = undefined
      $scope.nonEditable = ['createdAt', 'createdBy', 'modifiedAt']
      $scope.activeField = undefined
      $scope.objects = client.objects
      $scope.accessrights = []

      $scope.onSubscribedObject = (o) ->
        console.log '==== spinmodel onSubscribedModel called for '+o.id+' updating model..'
        #console.dir o
        for k,v of o
          $scope.model[k] = o[k]

      $scope.isEditable = (propname) =>
        rv = $scope.edit
        if propname in $scope.nonEditable then rv = false
        return rv

      $scope.$watch 'model', (newval, oldval) ->
        console.log 'spinmodel watch fired for '+newval
        #console.log 'edit is '+$scope.edit
        if $scope.model
          client.getRightsFor($scope.model.type).then (rights) -> $scope.accessrights[$scope.model.type] = rights
          if $scope.listprops and newval.id == oldval.id
            $scope.updateModel()
          else
            $scope.renderModel()
          if not $scope.subscription
            client.registerObjectSubscriber({ id: $scope.model.id, type: $scope.model.type, cb: $scope.onSubscribedObject}).then (listenerid) ->
              $scope.subscription = {sid: listenerid, o: $scope.model}

      success = (result) =>
        console.log 'success: '+result

      failure = (err) =>
        console.log 'error: '+err

      $scope.onChange = (model) =>
        console.log 'spinmodel onChange called for'
        console.dir model
        $scope.activeField = model.type
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
            client.emitMessage( {target:'_delete'+item.type, obj: {id: item.id, type:item.type}}).then (o)=>
              console.log 'deleted '+o.type+' on server'
          , failure)

      $scope.updateModel = () ->
        for k,v of $scope.model
          $scope.listprops.forEach (lp) ->
            console.log 'model.updateModel run for '+lp
            if lp.type
              client.getRightsFor(lp.type).then (rights) -> $scope.accessrights[lp.type] = rights
            if lp.name == k then lp.value = v

      $scope.renderModel = () =>
        #console.log 'spinmodel::renderModel called for '+$scope.model.name
        #console.dir $scope.model
        $scope.listprops = []
        client.getModelFor($scope.model.type).then (md) ->
          modeldef = {}
          md.forEach (modelprop) -> modeldef[modelprop.name] = modelprop
          if $scope.model
            $scope.listprops.push {name: 'id', value: $scope.model.id}
            #delete $scope.model.id
            for prop,i in md
              if prop.type
                client.getRightsFor(prop.type).then (rights) -> $scope.accessrights[prop.type] = rights
              notshow = prop.name in $scope.hideproperties
              #console.log 'spinmodel::renderModel '+prop.name+' -> '+$scope.model[prop.name]+' notshow = '+notshow
              if(prop.name != 'id' and not notshow and prop.name != $scope.activeField and $scope.model[prop.name])
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

      $scope.selectModel = (type, propname) ->
        client.emitMessage(target: '_list'+type+'s').then (objlist) ->
          $mdDialog.show
            controller: (scope) ->
              console.log '++++++++++++++ selectModel controller type='+type+', propname='+propname+' objlist is...'
              console.dir objlist
              list = []
              objlist.forEach (obj)-> list.push obj.id
              scope.list = list
              scope.type = type
              console.log 'list is'
              console.dir list
              scope.onselect = (model) ->
                console.log '* selectMode onselect callback'
                console.dir model
                $scope.model[propname].push(model.id)
                client.emitMessage({target:'updateObject', obj: $scope.model}).then(success, failure)
                $mdDialog.hide()
            template: '<md-dialog aria-label="selectdialog"><md-content><spinlist listmodel="type" list="list" onselect="onselect"></spinlist></md-content></md-dialog>'

      $scope.$on '$destroy', () =>
        s = $scope.subscription
        console.log 'spinmodel captured $destroy event s = '+s
        if s
          client.deRegisterObjectSubscriber(s.sid, s.o)

    }
  ]
.directive 'spinwalker', [
  'spinclient'
  (client) ->
    {
    restrict: 'AE'
    replace: false
    #templateUrl: 'spinwalker.html
    template:'<div>
    <span ng-repeat="crumb in breadcrumbs">
       <md-button ng-click="crumbClicked(crumb)">{{crumbPresentation(crumb)}}</md-button> >
    </span>
    <md-divider></md-divider>
    <spinmodel model="selectedmodel" edit="edit" onselect="onselect" hideproperties="hideproperties" style="height:400px;overflow:auto"></spinmodel>
</div>'
    scope:
      model: '=model'
      edit: '=edit'
      hideproperties: '='

    link: (scope, elem, attrs) ->

    controller: ($scope) ->
      $scope.selectedmodel = $scope.model
      $scope.breadcrumbs = [$scope.model]

      $scope.$watch 'model', (newval, oldval) ->
        console.log 'spinwalker model = '+$scope.model
        if($scope.model)
          console.dir $scope.model
          if not $scope.breadcrumbs
            console.log '************************************************* creating new breadcrumbs...'
            $scope.breadcrumbs = [$scope.model]
          $scope.selectedmodel = $scope.model

      $scope.crumbClicked = (model) ->
        #console.log '************************************************* crumbClicked selected model '+model.is+' '+model.type
        $scope.selectedmodel = model
        idx = -1
        for crumb, i  in $scope.breadcrumbs
          console.log '--- '+' crumb '+crumb.name+', id '+crumb.id
          if crumb.id == model.id then idx = i
        idx++ # take away all after that which we clicked
        #console.log '************************************************* crumbClicked crumbs length = '+$scope.breadcrumbs.length+' idx = '+idx
        #console.dir $scope.breadcrumbs
        #console.log 'clicked item is...'
        #console.dir model
        if idx > -1 and $scope.breadcrumbs.length > idx
          #console.log 'splicing at index '+idx
          $scope.breadcrumbs = $scope.breadcrumbs.slice 0, idx

      $scope.onselect = (model, replace) ->
        #console.log '************************************************* spinwalker onselect for model '+model.name+' replace = '+replace
        #console.log model
        if replace then $scope.breadcrumbs = []
        $scope.selectedmodel = model
        $scope.breadcrumbs.push model
        #console.log 'breadcrumbs are now'
        #console.dir $scope.breadcrumbs

      $scope.crumbPresentation = (crumb) =>
        crumb.name || crumb.type

    }
  ]
.directive 'spinlist', [
  'spinclient'
  (client) ->
    {
    restrict:    'AE'
    replace:     false
    #templateUrl: 'spinlist.html'
    template:'<div >
    <md-subheader class="md-no-sticky" style="background-color:#ddd">
                <md-icon md-svg-src="assets/images/ic_apps_24px.svg" ></md-icon>
                    List of {{listmodel}}s</md-subheader>
    <div ng-if="list.length>0" layout="row" style="height:55px" style="background-color:#e87d0d">
      <strong flex>Search:</strong>
      <md-input-container flex layout-align="left" style="min-height:20px">
        <md-select aria-label="search property" ng-model="qproperty" placeholder="name" ng-change="onsearchchange(qproperty)" style="padding:0px">
          <md-option ng-value="opt" ng-repeat="opt in objectmodel">{{ opt.name }}</md-option>
        </md-select>
      </md-input-container>
      <md-input-container flex layout-align="center" style="min-height:20px">
        <input aria-label="search value" type="text" ng-model="qvalue" required ng-change="onvaluechanged(qvalue)">
      </md-input-container>
    </div>
    <md-list >
        <md-list-item ng-repeat="item in expandedlist" layout="row">
            <md-button ng-if="edit" aria-label="delete" class="md-icon-button" ng-click="deleteItem(item)">
                <md-icon md-svg-src="assets/images/ic_delete_24px.svg"></md-icon>
            </md-button>
            <md-button  ng-click="selectItem(item)">
              <img ng-if="item.value" ng-src="item.value"> {{ objects[item.id].name }}
            </md-button>
        </md-list-item>
    </md-list>
</div>'
    scope:
      list: '=list'
      listmodel: '=listmodel'
      edit: '=edit'
      onselect: '&'
      ondelete: '&'

    link:        (scope, elem, attrs) ->
      scope.onselect = scope.onselect()
      scope.ondelete = scope.ondelete()

    controller:  ($scope) ->
      console.log '*** spinlist created. list is '+$scope.list+' items, type is '+$scope.listmodel
      console.dir $scope.list
      $scope.subscriptions = []
      $scope.expandedlist = []
      $scope.objects = client.objects
      $scope.objectmodel = undefined

      $scope.qvalue = ''
      $scope.qproperty = 'name'

      client.getModelFor($scope.listmodel).then (md) -> $scope.objectmodel = md

      success = (result) =>
        console.log 'success: '+result

      failure = (err) =>
        console.log 'error: '+err
        console.dir err

      $scope.onsearchchange = (v)->
        console.log 'onsearchchange called. v = '+v+' qprop = '+$scope.qproperty+', qval = '+$scope.qvalue

      $scope.onvaluechanged = (v)->
        console.log 'onvaluechange called. v = '+v+' qprop = '+$scope.qproperty+', qval = '+$scope.qvalue
        if $scope.qvalue
          q = {property: $scope.qproperty, value: $scope.qvalue, wildcard: true }
          console.log '---- query sent to server is..'
          console.dir q
          client.emitMessage({ target:'_list'+$scope.listmodel+'s', query: q}).then( (newlist) ->
            console.log 'search got back list of '+newlist.length+' items'
            $scope.list = []
            newlist.forEach (item)-> $scope.list.push item.id
            $scope.renderList())
        else
          client.emitMessage({ target:'_list'+$scope.listmodel+'s'}).then( (newlist2) ->
            $scope.list = []
            newlist2.forEach (item)-> $scope.list.push item.id
            $scope.renderList())

      $scope.selectItem = (item) =>
        #console.log 'item '+item.name+' selected'
        $scope.onselect(item, $scope.replace) if $scope.onselect

      $scope.deleteItem = (item) ->
        #console.log 'list delete'
        $scope.ondelete(item) if $scope.ondelete

      $scope.$watch 'list', (newval, oldval) ->
        $scope.renderList()

      $scope.renderList = () ->
        $scope.expandedlist = []
        if $scope.list
          for modelid in $scope.list
            console.log '**spinlist expanding list reference for model id '+modelid+' of type '+$scope.listmodel
            client.emitMessage({ target:'_get'+$scope.listmodel, obj: {id: modelid, type: $scope.listmodel }}).then( (o)->
              console.log 'spinlist _get got back object '+o
              console.dir o
              client.objects[o.id] = o
              for modid,i in $scope.list
                if modid == o.id
                  console.log '-- exchanging list id with actual list model from server for '+o.name
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
    replace:     false
    #templateUrl: 'spinhash.html'
    template: '<div>
    <md-subheader class="md-no-sticky" style="background-color:#ddd">
            <md-icon md-svg-src="assets/images/ic_apps_24px.svg" ></md-icon>
                Hash of {{listmodel}}s</md-subheader>
    <md-list>
        <md-list-item ng-repeat="item in expandedlist" layout="row">
          <md-button ng-if="!edit" aria-label="delete" class="md-icon-button" ng-click="deleteItem(item)">
              <md-icon md-svg-src="bower_components/material-design-icons/action/svg/production/ic_delete_24px.svg"></md-icon>
          </md-button> <md-button  ng-click="selectItem(item)">{{ objects[item.id].name }}</md-button>
    </md-list>
</div>'
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
      $scope.objects = client.objects
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

      $scope.selectItem = (item) =>
        #console.log 'item '+item.name+' selected'
        $scope.onselect(item, $scope.replace) if $scope.onselect

    }
  ]
