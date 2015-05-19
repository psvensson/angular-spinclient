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

    it 'should be able to set websocket instance', ->
      expect(server.emit).to.be.a('function')
