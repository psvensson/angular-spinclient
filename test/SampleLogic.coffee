Game  = require('./SampleGame')
DB    = require('spincycle').DB

class SampleLogic

  @gamecount = 0

  constructor: (@messageRouter) ->
    @games = []
    DB.createDatabases(['samplegame', 'sampleplayer']).then (results)=>
      console.log ' DB init done..'
      @messageRouter.objectManager.expose('SampleGame')
      @messageRouter.objectManager.expose('SamplePlayer')
      DB.getOrCreateObjectByRecord({id:17, name: 'fooGame', type: 'SampleGame'}).then (game)=>
        console.log 'got first game'
        game.serialize()

module.exports = SampleLogic