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
                service.infomessage = ''
                detail.d.reject reply
                break
              else
                #console.log 'delivering message '+message+' reply to '+detail.target+' to '+reply.messageId
                service.infomessage = reply.info
                service.failuremessage = ''
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
      #console.log 'registerObjectSubscriber localsubs is'
      #console.dir localsubs
      if not localsubs
        localsubs = []
        #console.log 'no local subs, so get the original server-side subscription for id '+detail.id
        # actually set up subscription, once for each object
        service._registerObjectSubscriber({id: detail.id, type: detail.type, cb: (updatedobj) ->
          #console.log '-- registerObjectSubscriber getting obj update callback for '+detail.id
          lsubs = service.objectsSubscribedTo[detail.id]
          #console.dir(lsubs)
          for k,v of lsubs
            if (v.cb)
              #console.log '--*****--*****-- calling back object update to local sid --****--*****-- '+k
              v.cb updatedobj
        }).then (remotesid) ->
          localsubs['remotesid'] = remotesid
          localsubs[sid] = detail
          #console.log '-- adding local callback listener to object updates for '+detail.id+' local sid = '+sid+' remotesid = '+remotesid
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
      d = $q.defer()
      try
        detail.messageId = uuid4.generate()
        detail.sessionId = service.sessionId
        detail.d = d
        service.outstandingMessages.push detail
        #console.log 'saving outstanding reply to messageId '+detail.messageId+' and sessionId '+detail.sessionId
        service.io.emit 'message', JSON.stringify(detail)
      catch e
        console.log 'spinclient emitMessage ERROR: '+e

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
    template:'<div style="padding:15px">
    <md-subheader class="md-no-sticky" style="background-color:#ddd">
            <md-icon md-svg-src="assets/images/ic_folder_shared_24px.svg" ></md-icon>
            {{model.type}} {{objects[model.id].name}}
    </md-subheader>
    <md-list flex>
      <md-list-item ng-repeat="prop in listprops" flex layout="row"  layout-fill>
        <md-input-container layout-padding layout-fill style="min-height:20px">
          <label flex="25"> {{prop.name}} </label>
          <span flex ng-if="prop.type && prop.value && !prop.hashtable && !prop.array">
              <md-button ng-click="enterDirectReference(prop)">{{prop.name}}</md-button> >
          </span>
          <input flex="50" ng-if="!isdate(prop.name) && !prop.array && !prop.type && isEditable(prop.name) && prop.name != \'id\'" type="text" ng-model="prop.value" ng-change="onChange(model, prop.name, prop.value)">
          <input flex="50" ng-if="!isdate(prop.name) && !prop.array && !prop.type && !isEditable(prop.name) || prop.name == \'id\'" type="text" ng-model="prop.value" disabled="true">

          <input flex="50" ng-if="isdate(prop.name)" type="datetime" value="{{prop.value}}" ng-disabled="true">

          <div layout-align="right" ng-if="accessrights[prop.type].create && (prop.array || prop.hashtable)"><md-button class="md-raised" ng-click="addModel(prop.type, prop.name)">New {{prop.type}}</md-button></div>
          <div layout-align="right" ng-if="accessrights[model.type].write && (prop.array || prop.hashtable)"><md-button class="md-raised" ng-click="selectModel(prop.type, prop.name)">Add {{prop.type}}</md-button></div>
          <spinlist ng-if="isEditable(prop.name) && prop.array" flex search="local" listmodel="prop.type" edit="edit" list="model[prop.name]" onselect="onselect" ondelete="ondelete"></spinlist>
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
      $scope.local = 'local'

      $scope.isdate = (name) ->
        name.indexOf('At')>-1

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

      $scope.onChange = (model, prop, val) =>
        console.log 'spinmodel onChange called for'
        model[prop] = val
        console.dir model
        $scope.activeField = model.type
        #console.dir prop
        client.emitMessage({target:'updateObject', obj: model}).then(success, failure)

      $scope.ondelete = (item) ->
        console.log 'model delete for list item'
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
            console.log 'update done'
            # actually delete the model formerly in the list
            # Nooooooooooooooooooo, default is do not. scheeeesh
            #client.emitMessage( {target:'_delete'+item.type, obj: {id: item.id, type:item.type}}).then (o)=>
            #  console.log 'deleted '+o.type+' on server'
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
              #console.log 'typeof $scope.model[prop.name] for '+prop.name+' is '+(typeof $scope.model[prop.name])
              #if(prop.name != 'id' and not notshow and prop.name != $scope.activeField and $scope.model[prop.name])
              if(prop.name != 'id' and not notshow and prop.name != $scope.activeField)
                if prop.name.indexOf('At') > -1
                  #val = $scope.model[prop.name]
                  val = new Date($scope.model[prop.name]).toString()
                else if typeof $scope.model[prop.name] == 'object'
                  #console.log '----stringifying----'
                  val = JSON.stringify($scope.model[prop.name])
                else
                  val = $scope.model[prop.name]
                #console.log('--- '+prop.name+' -> '+val+' resulting typeof is '+(typeof val))
                foo = {name: prop.name, value: val || "", type: modeldef[prop.name].type, array:modeldef[prop.name].array, hashtable:modeldef[prop.name].hashtable}
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
              scope.onlistmodeldelete = ()-> console.log 'onlistmodeldelete called. Ignoring this since we\'re in the middle of selecting'
              scope.onselect = (model) ->
                console.log '* selectModel onselect callback'
                console.dir model
                $scope.model[propname].push(model.id)
                client.emitMessage({target:'updateObject', obj: $scope.model}).then(success, failure)
                $mdDialog.hide()
            template: '<md-dialog aria-label="selectdialog"><md-dialog.content style="width:300px;margin:10px"><spinlist listmodel="type" list="list" onselect="onselect" ondelete="onlistmodeldelete" search="\'local\'"></spinlist></md-dialog.content></md-dialog>'

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
    <spinmodel model="selectedmodel" edit="edit" onselect="onselect" ondelete="ondelete" hideproperties="hideproperties" style="height:400px;overflow:auto"></spinmodel>
</div>'
    scope:
      model: '=model'
      edit: '=edit'
      ondelete: '=ondelete'
      hideproperties: '='

    link: (scope, elem, attrs) ->

    controller: ($scope) ->
      console.log 'spinwalker model originally is'
      console.dir $scope.model
      if typeof $scope.replace == 'undefined' then $scope.replace = true
      $scope.selectedmodel = $scope.model
      $scope.breadcrumbs = [$scope.model]

      $scope.$watch 'model', (newval, oldval) ->
        console.log 'spinwalker model = '+$scope.model
        console.log 'newval is..'
        console.dir newval
        console.log 'oldval is'
        console.dir oldval
        if oldval isnt newval
          if($scope.model)
            if not $scope.breadcrumbs
              console.log '************************************************* creating new breadcrumbs...'
              $scope.breadcrumbs = [$scope.model]
            $scope.selectedmodel = $scope.model
          $scope.onselect($scope.model, $scope.replace)

      $scope.crumbClicked = (model) ->
        $scope.selectedmodel = model
        idx = -1
        for crumb, i  in $scope.breadcrumbs
          console.log '--- '+' crumb '+crumb.name+', id '+crumb.id
          if crumb.id == model.id then idx = i
        idx++ # take away all after that which we clicked
        if idx > -1 and $scope.breadcrumbs.length > idx
          #console.log 'splicing at index '+idx
          $scope.breadcrumbs = $scope.breadcrumbs.slice 0, idx

      $scope.onselect = (model) ->
        console.log 'spinwalker.onselect model '+model+' replace '+$scope.replace
        if $scope.replace then $scope.breadcrumbs = []
        $scope.selectedmodel = model
        console.log 'pushing..'
        $scope.breadcrumbs.push model

      $scope.crumbPresentation = (crumb) -> crumb.name || crumb.type

    }
  ]
.directive 'spinlistmodel', [
  'spinclient'
  (client) ->
    {
    restrict: 'AE'
    replace: true
    template: '<div >
      <spinlist listmodel="listmodel" list="list" onselect="onourselect" replace="replace" ondelete="onourdelete" edit="edit" search="search" searchfunc="searchfunc"></spinlist>
    </div>'
    scope:
      listmodel: '=listmodel'
      edit: '=edit'
      onselect: '&'
      ondelete: '&'

    link: (scope, elem, attrs) ->
      scope.onselect = scope.onselect()
      scope.ondelete = scope.ondelete()

    controller: ($scope) ->
      $scope.onourselect = (item)->
        console.log 'spinlistmodel our select called. provided select is '+$scope.onselect
        $scope.onselect(item) if $scope.onselect

      $scope.onourdelete = (item) ->
        console.log 'spinlistmodel delete called'
        if $scope.ondelete
          $scope.ondelete(item)
        else
          client.emitMessage( {target:'_delete'+item.type, obj: {id: item.id, type: item.type}}).then (o) =>
            console.log 'deleted '+o.type+' on server'

      $scope.search = 'server'
      console.log '*** spinlistmodel created, type is ' + $scope.listmodel + ', search is ' + $scope.search
      client.emitMessage({ target:'_list'+$scope.listmodel+'s'}).then (newlist2) ->
        tmp = []
        newlist2.forEach (item)-> tmp.push item.id
        console.log 'spinlistmodel list is now '+tmp
        $scope.list = tmp

      $scope.searchfunc = (v, qprop, qval, selectedindex) ->
        console.log 'spinlistmodel - searchfunc'
        console.dir arguments
        if v
          if qprop == 'id'
            q = {property: qprop, value: v or ''}
          else
            q = {property: qprop, value: v or '', limit:10, skip: 10*selectedindex, wildcard: !!v}
          console.log '---- query sent to server is..'
          console.dir q
          client.emitMessage({ target:'_list'+$scope.listmodel+'s', query: q}).then (newlist) ->
            console.log 'search got back list of '+newlist.length+' items'
            tmp = []
            newlist.forEach (item)-> tmp.push item.id
            $scope.list = tmp
        else
          client.emitMessage({ target:'_list'+$scope.listmodel+'s'}).then (newlist2) ->
            tmp = []
            newlist2.forEach (item)-> tmp.push item.id
            $scope.list = tmp
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
    <div ng-if="list" layout="row" >
      <md-input-container flex style="padding:0">
        <label>Property:</label>
        <md-select aria-label="search property" ng-model="qproperty" placeholder="name" ng-change="onsearchchange(qproperty)" >
          <md-option ng-value="opt" ng-repeat="opt in objectmodel" value="{{opt.name}}">{{ opt.name }}</md-option>
        </md-select>
      </md-input-container>
      <md-input-container flex layout-align="center" style="padding:0">
        <label>Search:</label>
        <input aria-label="search value" type="text" ng-model="qvalue" required ng-change="onvaluechanged(qvalue)">
      </md-input-container>
    </div>
    <md-list flex>
        <md-list-item ng-repeat="item in expandedlist track by item.id" layout="row" style="min-height:10px">
            <md-button ng-if="edit" aria-label="delete" class="md-icon-button" ng-click="deleteItem(item)">
                <md-icon md-svg-src="assets/images/ic_delete_24px.svg"></md-icon>
            </md-button>
            <md-button  ng-click="selectItem(item)">
              <img ng-if="item.value" ng-src="item.value"> {{ objects[item.id].name }}
            </md-button>
        </md-list-item>
    </md-list>
    <div ng-if="listcount.length>0" style="padding:15px">
      <span ng-style="setIndexStyle($index)" ng-click="selectPage($index)" ng-repeat="n in listcount track by $index"> {{$index}}</span>
    </div>
</div>'
    scope:
      list: '=list'
      listmodel: '=listmodel'
      edit: '=edit'
      search: '=search'
      onselect: '&'
      ondelete: '&'
      searchfunc: '&'

    link:        (scope, elem, attrs) ->
      scope.onselect = scope.onselect()
      scope.ondelete = scope.ondelete()
      scope.searchfunc = scope.searchfunc()

    controller:  ($scope) ->
      $scope.search = $scope.search or 'local'
      $scope.list = $scope.list or []
      #console.log '* * spinlist created. list is '+$scope.list+' items, type is '+$scope.listmodel+', search is '+$scope.search
      #console.log 'ondelete = '+$scope.ondelete+' onselect = '+$scope.onselect
      #console.dir $scope.list
      $scope.subscriptions = []
      $scope.expandedlist = []
      $scope.objects = client.objects
      $scope.objectmodel = []
      $scope.selectedindex = 0

      $scope.listcount = []

      $scope.qvalue = ''
      $scope.qproperty = 'name'
      $scope.origlist = $scope.list

      client.getModelFor($scope.listmodel).then (md) ->
        $scope.objectmodel = md
        $scope.objectmodel.push {name:'id',public:true, value:'id'}
        #console.log '** objectmodel for list is **'
        #console.dir md

      success = (result) =>
        console.log 'success: '+result

      failure = (err) =>
        console.log 'error: '+err
        console.dir err

      #-----------------------------------------------------------------------------------------------------------------

      $scope.setIndexStyle = (i)->
        #console.log 'setIndexStyle i='+i+', selectedIndex='+$scope.selectedindex
        if i != $scope.selectedindex
          rv = {color:"black", "background-color":"white",padding:"20px"}
        else
          rv = {color:"white", "background-color":"black",padding:"20px"}
        rv

      $scope.selectPage = (p)->
        console.log '********************************************************* page '+p+' selected'
        $scope.selectedindex = p

        ###q = {property: $scope.qproperty, value: $scope.qvalue or '', limit:10, skip: 10*p, wildcard: !!$scope.qvalue}
        client.emitMessage({ target:'_list'+$scope.listmodel+'s', query: q}).then( (newlist) ->
          console.log 'paged search got back list of '+newlist.length+' items'
          tmp = []
          newlist.forEach (item)-> tmp.push item.id
          $scope.list = tmp
          $scope.renderList())###

        $scope.renderList()

      $scope.onsearchchange = (v)->
        #console.log 'onsearchchange *'
        #$scope.qvalue = v
        console.log '* onsearchchange called. v = '+v+' qprop = '+$scope.qproperty+', qval = '+$scope.qvalue
        if $scope.search != 'local' then $scope.doSearch($scope.qproperty, v) else $scope.localSearch(v)

      $scope.onvaluechanged = (v)->
        #console.log '* onvaluechange called. v = '+v+' qprop = '+$scope.qproperty+', qval = '+$scope.qvalue
        if $scope.search != 'local' then $scope.doSearch($scope.qproperty, v) else $scope.localSearch(v)

      $scope.doSearch = (prop, v) ->
        #console.log '*** dosearch called. v = '+v+' prop = '+prop+', qval = '+$scope.qvalue
        #console.dir v
        if $scope.searchfunc then $scope.searchfunc(v, prop, $scope.qvalue, $scope.selectedindex) else console.log 'no searchfunc defined'

      $scope.localSearch = (v) ->
        #console.log 'localSearch called. v = '+v
        tmp = []
        $scope.origlist.forEach (id) ->
          item = client.objects[id]
          #console.log 'localSearch comparing property '+$scope.qproperty+' which is '+item[$scope.qproperty]+' to see if it is '+v
          if v
            if (""+item[$scope.qproperty]).indexOf(v) > -1 then tmp.push item.id
          else
            tmp.push item.id
        tmp.sort (a,b)-> if a == b then 0 else if a > b then 1 else -1
        $scope.list = tmp
        $scope.renderList()

      $scope.selectItem = (item) =>
        console.log 'item '+item.name+' selected'
        $scope.onselect(item, $scope.replace) if $scope.onselect

      $scope.deleteItem = (item) ->
        console.log 'list item delete clicked. $scope.ondelete = '+$scope.ondelete
        if $scope.ondelete then $scope.ondelete(item)

      $scope.$watch 'list', (newval, oldval) ->
        $scope.renderList()

      $scope.renderPageSelector = () ->
        #console.log 'renderpageselector called'
        count = $scope.list.length
        if count < 10
          $scope.listcount.length = 1
        else
          $scope.listcount.length = parseInt(count/10) + ((count % 10) > 0 ? 1 : 0)
        $scope.totalcount = count
        #console.log 'renderpageSelector - listcount = '+$scope.listcount.length+' expandedlist is '+$scope.expandedlist.length+', count = '+count
        console.dir $scope.expandedlist

      $scope.renderList = () ->
        console.log 'renderList called'
        $scope.renderPageSelector()
        $scope.expandedlist = []
        base = $scope.selectedindex*10
        #console.log 'renderList - listcount = '+$scope.listcount.length+', base = '+base
        slice = $scope.list
        if $scope.list.length > 10
          slice = []
          for x in [base..base+10]
            id = $scope.list[x]
            #console.log 'adding slice '+id
            slice.push(id)

        for modelid,i in slice
          #console.log '**spinlist expanding list reference for model id '+modelid+' of type '+$scope.listmodel
          if client.objects[modelid]
            #console.log 'found model '+i+' in cache '+modelid
            #console.dir(client.objects[modelid])
            $scope.addExpandedModel(client.objects[modelid], slice)
          else
            #console.log 'fetching model '+i+' from server '+modelid
            client.emitMessage({ target:'_get'+$scope.listmodel, obj: {id: modelid, type: $scope.listmodel }}).then( (o)->
              client.objects[o.id] = o
              #console.log 'got back from server '+o.id+' -> '+o
              $scope.addExpandedModel(o, slice)
            , failure)

      $scope.addExpandedModel = (o, list) ->
        for modid,i in list
          if modid == o.id
            #console.log 'addExpandedModel -- exchanging list id '+o.id+' with actual list model from server'
            #console.dir(o)
            $scope.expandedlist[i] = o

      $scope.onSubscribedObject = (o) ->
        #console.log 'onSubscribedObject called ++++++++++++++++++++++++'
        #console.dir(o)
        added = false
        for model,i in $scope.list
          if model.id == o.id
            #console.log 'found match in update for object '+o.id+' name '+o.name
            mod = $scope.expandedlist[i]
            for k,v of o
              added = true
              mod[k] = v
        if not added
          #console.log 'adding new subscribed object to expanded list.. '+o.id
          #console.dir o
          $scope.expandedlist.push(o)
        $scope.$apply()

      #console.log 'subscribing to list ids..'
      $scope.list.forEach (id) ->
        #console.log 'subscribing to list id '+id
        if id
          client.registerObjectSubscriber(
            id: id
            type: $scope.listmodel
            cb: $scope.onSubscribedObject
          ).then (listenerid) ->
            $scope.subscriptions.push {sid: listenerid, o: {type:$scope.listmodel, id: id}}

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
.directive 'spingrid', [
  'spinclient', '$mdDialog'
  (client, $mdDialog) ->
    {
    restrict:    'AE'
    replace:     false
    template: '<div>
    <md-subheader class="md-no-sticky" style="background-color:#ddd">
            <md-icon md-svg-src="assets/images/ic_apps_24px.svg" ></md-icon>
                Grid of {{listmodel}}s</md-subheader>
    <md-grid-list md-cols="{{ocols}}" md-row-height="35px" style="margin-right:16px">
      <md-grid-tile ng-repeat="prop in objectmodel" style="background-color: #cacaca">
        {{prop.name}}
      </md-grid-tile>
      <md-grid-tile ng-repeat="cell in cells" style="height:15px" layout-fill>
        <md-button raised ng-if="onselect" ng-click="selectItem(cell.item)">Select</md-button>
        <span flex ng-if="cell.prop.type && cell.prop.value && !cell.prop.hashtable && !cell.prop.array" ng-click="enterDirectReference(prop)">{{cell.item[cell.prop.name]}}</span>
        <input layout-fill flex ng-if="!cell.prop.array && !cell.prop.type &&  isEditable(cell.prop.name) && cell.prop.name != \'id\'" type="text" ng-model="cell.item[cell.prop.name]" ng-change="onChange(cell.item, cell.prop.name)">
        <input layout-fill flex ng-if="!cell.prop.array && !cell.prop.type && !isEditable(cell.prop.name) && cell.prop.name != \'id\'" type="text" ng-model="cell.item[cell.prop.name]" disabled="true">
        <span flex ng-if="isEditable(cell.prop.name) && (cell.prop.array || cell.prop.hashtable)" ng-model="cell.item[cell.prop.name]" ng-click="selectModel(cell.item, cell.prop.type, cell.prop.name)">{{cell.item[cell.prop.name].length}} {{cell.prop.name}}</span>
        <span flex ng-if="!isEditable(cell.prop.name) && (cell.prop.array || cell.prop.hashtable)" >{{cell.item[cell.prop.name].length}} {{cell.prop.name}}</span>
      </md-grid-tile>
    </md-grid-list>
</div>'
    scope:
      list: '=list'
      listmodel:   '=listmodel'
      onselect:    '&'
      ondelete:    '&'
      edit:        '=edit'

    link: (scope, elem, attrs) ->
      scope.onselect = scope.onselect()

    controller: ($scope) ->
      console.log 'spingrid list for model '+$scope.listmodel+' is'
      console.dir $scope.list

      $scope.objects = client.objects
      $scope.expandedlist = []
      $scope.objectmodel = []
      $scope.ocols = 4
      $scope.cells = []
      $scope.nonEditable = ['createdAt', 'createdBy', 'modifiedAt']

      $scope.isEditable = (propname) =>
        rv = $scope.edit
        if not propname then rv = false
        if propname in $scope.nonEditable then rv = false
        #console.log 'isEditable returned '+rv+' for '+propname
        return rv

      client.getModelFor($scope.listmodel).then (md) ->
        $scope.objectmodel = md
        $scope.objectmodel.push {name:'id',public:true, value:'id'}
        $scope.ocols = md.length
        for mid in $scope.list
          client.emitMessage({ target:'_get'+$scope.listmodel, obj: {id: mid, type: $scope.listmodel }}).then( (o)->
            for modid,i in $scope.list
              if modid == o.id
                console.log 'adding hashtable element '+o.name
                $scope.expandedlist[i] = o
                client.objects[o.id] = o
                for k,v of $scope.objectmodel
                  $scope.cells.push {item: o, prop: v}
                  #console.log 'adding cell '+o.name+' - '+v.name
                  #console.dir {item: o, prop: v}
          , failure)

      failure = (err) =>
        console.log 'error: '+err
        console.dir err

      success = (result) =>
        console.log 'success: '+result

      $scope.selectItem = (item) =>
        console.log 'spingrid selected item '+item
        console.dir(item)
        deepclone = JSON.parse(JSON.stringify(item))
        $scope.onselect(deepclone, $scope.replace) if $scope.onselect

      $scope.onChange = (model) =>
        console.log 'spingrid onChange called for'
        console.dir model
        $scope.activeField = model.type
        #console.dir prop
        client.emitMessage({target:'updateObject', obj: model}).then(success, failure)

      $scope.selectModel = (item, type, propname) ->
        console.log 'selectModel called for prop '+propname+' type '+type
        objlist = item[propname]
        $mdDialog.show
          controller: (scope) ->
            console.log '++++++++++++++ spingrid selectModel controller type='+type+', propname='+propname+' objlist is...'
            console.dir objlist
            list = []
            objlist.forEach (id)-> list.push id
            scope.list = list
            scope.type = type
            scope.item = item
            scope.propname = propname

            scope.addModel = (item, type, propname) ->
              console.log 'spingrid.addModel called for type '+type+' propname '+propname
              console.dir item
              client.emitMessage({target:'_create'+type, obj: {name: 'new '+type, type:type}}).then((o) =>
                item[propname].push(o.id)
                console.log 'update list after addition'
                console.dir item[propname]
                scope.list = item[propname]
                client.emitMessage({target:'updateObject', obj: item}).then(success, failure)
              , failure)

            scope.ondelete = (arrayitem) ->
              client.getModelFor(item.type).then (md) ->
                propname = undefined
                console.log 'item'
                console.dir item
                md.forEach (m) -> propname = m.name if m.type == arrayitem.type
                li = item[propname]
                console.log 'li'
                console.dir li
                idx = -1
                for mid,i in li
                  if mid == arrayitem.id then idx = i
                if idx > -1 then li.splice idx,1
                item[propname] = li
                scope.list = item[propname]
                client.emitMessage({target:'updateObject', obj: item}).then ()->
                  console.log 'update list after deletion'
                  console.dir li

            console.log 'list is'
            console.dir list

            scope.hide = () ->
              console.log 'hiding dialog'
              $mdDialog.hide()

            scope.onselect = (model) ->
              console.log '* spingrid selectMode onselect callback'
              console.dir model
              exists = false
              console.log '-- checking for dupes --'
              console.dir item[propname]
              for id in item[propname]
                console.log 'testing if existing list model '+id+' matches new addition '+model.id
                if id == model.id then exists = true
              if not exists
                console.log '-- adding new model to list'
                item[propname].push model.id
                scope.list = item[propname]
                client.emitMessage({target:'updateObject', obj: item}).then(success, failure)
              else
                console.log 'avoiding adding duplicate!'
              $mdDialog.hide()

          template: '<md-dialog aria-label="selectdialog">
                      <md-dialog-content style="width:300px;margin:10px">
                        <md-button class="md-raised" ng-click="addModel(item, type, propname)">New {{type}}</md-button>
                        <md-button class="md-raised" ng-click="hide()">Close</md-button>
                        <spinlist listmodel="type" list="list" edit="true" onselect="onselect" ondelete="ondelete"></spinlist>
                      </md-dialog-content>
                     </md-dialog>'



    }
]