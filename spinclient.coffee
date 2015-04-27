angular.module('angular-spinclient', ['uuid4', 'ngWebSocket', 'ngMaterial']).factory 'ngSpinClient', (uuid4, $websocket, $q) ->
  #public methods & properties
  service = {

    subscribers         : []
    objsubscribers      : []
    outstandingMessages : []
    modelcache          : []
    #io                  : $websocket('ws://localhost:3003')
    io                  : io('ws://localhost:3003')

    registerListener: (detail) ->
      subscribers = service.subscribers[detail.message] or []
      subscribers.push detail.callback
      service.subscribers[detail.message] = subscribers
      return

    registerObjectSubscriber: (detail) ->
      #console.dir(detail);
      d = $q.defer()
      #console.log 'message-router registering subscriber for object ' + detail.id + ' type ' + detail.type
      subscribers = service.objsubscribers[detail.id] or []
      subscribers.push detail.cb
      service.objsubscribers[detail.id] = subscribers
      service.emitMessage(
        target: 'registerForUpdatesOn'
        messageId: uuid4.generate()
        obj: {id: detail.id, type: detail.type}).then (reply) ->
          d.resolve(reply)
      return d.promise

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
    if subscribers.length == 0
      console.log '* OH NOES! * No subscribers for object update on object ' + obj.id
      console.dir service.objsubscribers
    else
      subscribers.forEach (subscriber) ->
        subscriber obj
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
  'ngSpinClient'
  (client) ->
    {
    restrict: 'AE'
    replace: true
    templateUrl: 'alltargets.html'
    link: (scope, elem, attrs) ->

    controller: ($scope) ->
      $scope.results = []
      console.log 'alltargets controller'

      $scope.onitemselect = (item) =>
        console.log 'alltargets item selected '+item.id
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

    }
  ]
.directive 'spinmodel', [
  'ngSpinClient'
  (client) ->
    {
    restrict:    'AE'
    replace:     true
    templateUrl: 'spinmodel.html'
    scope:
      model: '=model'
      edit: '=edit'

    link:        (scope, elem, attrs) ->

    controller:  ($scope) ->
      $scope.isarray = angular.isArray

      $scope.$watch 'model', (newval, oldval) ->
        console.log 'model is'
        console.dir $scope.model
        #console.log 'edit is '+$scope.edit
        $scope.listprops = []
        client.getModelFor($scope.model.type).then (md) ->
          modeldef = {}
          md.forEach (modelprop) -> modeldef[modelprop.name] = modelprop
          if $scope.model
            $scope.listprops.push {name: 'id', value: $scope.model.id}
            #delete $scope.model.id
            for prop,i in md
              if(prop.name != 'id' and angular.isArray($scope.model[prop.name]) == no)
                $scope.listprops.push {name: prop.name, value: $scope.model[prop.name] || "", type: modeldef[prop.name]?.type}
            for prop,i in md
              if(prop.name != 'id' and  angular.isArray($scope.model[prop.name]) == yes)
                $scope.listprops.push {name: prop.name, value: $scope.model[prop.name], type: modeldef[prop.name]?.type}

      success = (result) =>
        console.log 'success: '+result

      failure = (err) =>
        console.log 'error: '+err

      $scope.onChange = (model,prop) =>
        console.log 'onChange called for'
        console.dir model
        console.dir prop
        client.emitMessage({target:'updateObject', obj: model}).then(success, failure)

      $scope.addModel = (type, propname) ->
        console.log 'addModel called for type '+type
        client.emitMessage({target:'_create'+type, obj: {name: 'new '+type, type:type}}).then((o)=>
          ## TODO: actually add the new object id to the list and update the container object
          console.log 'addModel for '+type+' got back object id for new instance = '+o.id
          $scope.model[propname].push(o)
          console.log 'parent model is now'
          console.dir $scope.model
          client.emitMessage({target:'_update'+$scope.model.type, obj: client.flattenModel($scope.model)}).then(success, failure)
        , failure)

    }
  ]
.directive 'spinlist', [
  'ngSpinClient'
  (client) ->
    {
    restrict:    'AE'
    replace:     true
    templateUrl: 'spinlist.html'
    scope:
      list: '=list'
      listmodel: '=listmodel'
      onselect: '&'
    link:        (scope, elem, attrs) ->
      scope.onselect = scope.onselect()

    controller:  ($scope) ->
      console.log 'spinlist created. list is '+$scope.list+' type is '+$scope.listmodel
      $scope.subscriptions = []
      $scope.objects = []
      $scope.expandedlist = []

      success = (result) =>
        console.log 'success: '+result

      failure = (err) =>
        console.log 'error: '+err

      $scope.selectItem = (item) =>
        #console.log 'item '+item.name+' selected'
        $scope.onselect(item) if $scope.onselect

      for modelid in $scope.list
        client.emitMessage({ target:'_get'+$scope.listmodel, obj: {id: modelid, type: $scope.listmodel }}).then( (o)->
          for mid,i in $scope.list
            if mid == o.id then $scope.list[i] = o
        , failure)

      $scope.onSubscribedObject = (o) ->
        console.log 'onSubscribedObject called ++++++++++++++++++++++++'
        console.dir(o)
        for model,i in $scope.list
          if model.id == o.id
            console.log 'found match in update for object '+o.id+' name '+o.name
            for k,v of o
              model[k] = v
        $scope.$apply()

      #console.log 'subscribing to list ids..'
      $scope.list.forEach (id) ->
        if id
          client.registerObjectSubscriber(
            id: id
            type: $scope.listmodel
            cb: $scope.onSubscribedObject
          ).then (listenerid) ->
            $scope.subscriptions.push listenerid

    }
  ]

