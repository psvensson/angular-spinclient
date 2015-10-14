SuperModel      = require('spincycle').SuperModel
defer           = require('node-promise').defer
uuid            = require('node-uuid')

class SamplePlayer extends SuperModel

  @type       = 'SamplePlayer'

  @model =
    [
      {name: 'name', public: true, value: 'name', default:  'player'}
    ]

  constructor: (@record={}) ->
    return super

module.exports = SamplePlayer