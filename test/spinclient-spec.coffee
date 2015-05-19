describe 'Spinclient', ->
  console.log 'testing started'

  spinclient = undefined
  beforeEach module('ngSpinclient')
  beforeEach inject((_spinclient_) ->
    spinclient = _spinclient_
  )
  describe 'Constructor', ->
    it 'should work', ->
      expect({foo:'bar'}).to.have.property 'foo', 'bar'
