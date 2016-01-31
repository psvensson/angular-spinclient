SuperModel      = require('spincycle').SuperModel
defer           = require('node-promise').defer
all             = require('node-promise').allOrNone
uuid            = require('node-uuid')
SamplePlayer    = require('./SamplePlayer')
FooThing        = require('./FooThing')

class SampleGame extends SuperModel

  @type       = 'SampleGame'
  @model =
    [
      {name: 'players', public: true,   array: true,   type: 'SamplePlayer', ids: 'players' }
      {name: 'name',    public: true,   value: 'name', default: 'game_'+uuid.v4() }
    ]

  constructor: (@record) ->
    return super

  postCreate: (q) =>
    console.log 'players.length == '+@players.length
    #console.dir @
    if @players.length == 0
      @createPlayers().then () =>
        q.resolve(@)
    else
      q.resolve(@)

  createPlayers: () =>
    console.log 'creating sample players'
    q = defer()
    @players = []
    new SamplePlayer({name: 'player 1', createdBy: 'SYSTEM', createdAt: Date.now()}).then (p1) =>
      new SamplePlayer({name: 'player 2',createdBy: 'SYSTEM', createdAt: Date.now()}).then (p2) =>
        new FooThing({name: 'ft1',createdBy: 'SYSTEM', createdAt: Date.now()}).then (ft1) =>
          new FooThing({name: 'ft2',createdBy: 'SYSTEM', createdAt: Date.now()}).then (ft2) =>
            console.log 'adding player '+p1.name
            p1.foohash[ft1.name] = ft1
            p1.foohash[ft2.name] = ft2
            ft1.serialize()
            ft2.serialize()
            #console.dir player
            @players.push p1
            console.log 'adding player '+p2.name
            @players.push p2
            p1.serialize()
            p2.serialize()
            @serialize()
            q.resolve()
    return q


module.exports = SampleGame