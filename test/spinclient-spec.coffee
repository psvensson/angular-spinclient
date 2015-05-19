describe 'Spinclient', ->
  console.log 'testing started'

  spinclient = undefined
  server = undefined

  beforeEach module('ngSpinclient', 'MockServer')
  beforeEach inject((_spinclient_, mockserver) ->
    spinclient = _spinclient_
    server = mockserver
    spinclient.setWebSocketInstance(server)
  )

  describe 'Constructor', ->
    it 'should work', ->
      expect(server.emit).to.be.a('function')

    it 'should be able to register an object subscriber', ->
      spinclient.registerObjectSubscriber({id:1, type: 'Foo', cb: (obj) ->
        console.log 'object update'
        console.dir obj
      })
      expect(server.emit).to.be.a('function')
