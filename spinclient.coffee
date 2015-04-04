angular.module('angular-spinclient', ['uuid4', 'ngWebSocket']).factory 'ngSpinClient', (uuid4, $websocket, $q) ->
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
      #console.dir(arguments);
      console.log 'message-router registering subscriber for object ' + detail.obj.id + ' type ' + detail.obj.type
      subscribers = service.objsubscribers[detail.obj.id] or []
      subscribers.push detail.callback
      service.objsubscribers[detail.obj.id] = subscribers
      service.io.emit 'message', JSON.stringify(
        target: 'registerForUpdatesOn'
        messageId: uuid4.generate()
        obj: detail.obj)
      return

    emitMessage : (detail) ->
      console.log 'emitMessage called'
      console.dir detail
      detail.messageId = uuid4.generate()
      service.outstandingMessages.push detail
      service.io.emit 'message', JSON.stringify(detail)
      return

    # ------------------------------------------------------------------------------------------------------------------

    listTargets: () ->
      d = $q.defer()
      service.emitMessage {
        target:'listcommands', callback:(targets)->
          d.resolve(targets);
      }
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
          detail.callback message
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
    template: '<div ng-repeat="target in targets">{{target.name}}</div>'
    link: (scope, elem, attrs) ->

    controller: ($scope) ->
      console.log 'alltargets controller'
      client.listTargets().then (_targets) ->
        $scope.targets = []
        for k,v of _targets
          $scope.targets.push {name:k, args:v}

    }
]

