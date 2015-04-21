angular.module('angular-spinclient', ['uuid4', 'ngWebSocket', 'ngMaterial']).factory 'ngSpinClient', (uuid4, $websocket, $q) ->
  #public methods & properties
  service = {

    subscribers         : []
    objsubscribers      : []
    outstandingMessages : []
    #io                  : $websocket('ws://localhost:3003')
    io                  : io('ws://localhost:3003')

    registerListener: (detail) ->
      subscribers = service.subscribers[detail.message] or []
      subscribers.push detail.callback
      service.subscribers[detail.message] = subscribers
      return

    registerObjectSubscriber: (detail) ->
      console.dir(detail);
      d = $q.defer()
      console.log 'message-router registering subscriber for object ' + detail.id + ' type ' + detail.type
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
      console.log 'emitMessage called'
      console.dir detail
      d = $q.defer()
      detail.messageId = uuid4.generate()
      service.outstandingMessages.push detail
      service.io.emit 'message', JSON.stringify(detail)
      detail.d = d
      return d.promise

    # ------------------------------------------------------------------------------------------------------------------

    listTargets: () ->
      d = $q.defer()
      service.emitMessage({target:'listcommands'}).then((targets)-> d.resolve(targets))
      return d.promise
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
    console.log 'got reply id ' + reply.messageId + ' status ' + status + ', info ' + info + ' data ' + message
    console.dir reply
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
          $scope.targets.push {name:k, args:v}

      success = (results)->
        $scope.results = results
        console.dir($scope.results)

      failure = (reply) ->
        console.log 'failure'+reply
        $scope.status = reply.status + ' - ' +reply.info

      $scope.callTarget = (t) ->
        $scope.status = "";
        console.log 'calltarget called with '+t.name
        client.emitMessage({target:t.name}).then(success,failure)

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
      console.log 'model is'
      console.dir $scope.model
      $scope.listprops = []
      if $scope.model
        for k,v of $scope.model
          console.log 'adding model prop '+k+' -> '+v
          $scope.listprops.push {name: k, value: v}
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

      $scope.selectItem = (item) =>
        console.log 'item '+item.name+' selected'
        $scope.onselect(item) if $scope.onselect

      $scope.onSubscribedObject = (o) ->
        console.log 'onSubscribecObject called ++++++++++++++++++++++++'
        $scope.objects[o.id] = o
        $scope.expandedlist = []
        for k,v of $scope.objects
          $scope.expandedlist.push v

      console.log 'subscribing to list ids..'
      $scope.list.forEach (obj) ->
        client.registerObjectSubscriber(
          id: obj.id
          type: $scope.listmodel
          cb: $scope.onSubscribedObject
        ).then (listenerid) ->
          $scope.subscriptions.push listenerid


    }
  ]

