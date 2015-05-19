do (angular) ->
  'use strict'

  angular.module('MockServer', []).factory 'mockserver', ->
    service =
    {
      callbacks: [],
      clientReplyFunc: undefined,
      blacklist: ['id', 'createdAt', 'modifiedAt'],
      subscribers: [],
      listenerid:0,
      objects: { 1: {id:1, name:'Foo 1', type:'Foo', createdAt: Date.now(), modifiedAt: undefined }, 2: {id:2, name: 'Bar 1', type:'Bar', createdAt: Date.now(), modifiedAt: undefined } },

      'on': (channel, callback) ->
        console.log 'mockserver on called for channel "'+channel+'"'
        console.dir
        service.callbacks[channel] = callback
        service.clientReplyFunc = callback

      'emit': (channel, message) ->
        console.log 'mockserver emit called for channel "'+channel+'"'
        console.dir message
        switch message.target
          when 'getModelFor'            then service.getModelFor(message)
          when 'registerForUpdatesOn'   then service.registerForUpdatesOn(message)
          when 'deRegisterForUpdatesOn' then service.deRegisterForUpdatesOn(message)
          when 'updateObject'           then service.updateObject(message)

          when 'Foo_create'             then service.createFoo(msg)
          when 'Foo_delete'             then service.deleteFoo(msg)
          when 'Foo_get'                then service.getFoo(msg)
          when 'Foo_list'               then service.listFoo(msg)

          when 'Bar_create'             then service.createBar(msg)
          when 'Bar_delete'             then service.deleteBar(msg)
          when 'Bar_get'                then service.getBar(msg)
          when 'Bar_list'               then service.listBar(msg)


      getModelFor: (msg) ->
        service.clientReplyFunc({messageId: msg.messageId, status: 'SUCCESS', info:'get model', payload:[ { name: 'name', public: true, value: 'name' }, { name: 'createdAt',    public: true,   value: 'createdAt'}, { name: 'modifiedAt',   public: true,   value: 'modifiedAt' }] })

      registerForUpdatesOn: (msg) ->
        subs = service.subscribers[msg.obj.id] or []
        subs[service.listenerid++] = (o) ->
          service.clientReplyFunc({status: e.general.SUCCESS, info: e.gamemanager.OBJECT_UPDATE, payload: o })
        service.subscribers[msg.obj.id] = subs

      deRegisterForUpdatesOn: (msg) ->
        subs = service.subscribers[msg.id] or []
        delete subs[msg.listenerid]

      updateObject: (msg) ->
        o = service.objects[msg.obj.id]
        for k,v of msg.obj
          if not k in service.blacklist then o[k] = msg.obj[k]
        for lid, cb of service.subscribers[msg.obj.id]
          cb(o)

      createFoo: (msg) ->


      deleteFoo: (msg) ->


      getFoo: (msg) ->


      listFoo: (msg) ->


      createBar: (msg) ->


      deleteBar: (msg) ->


      getBar: (msg) ->


      listBar: (msg) ->

    }

    return service


