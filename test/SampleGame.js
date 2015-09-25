// Generated by CoffeeScript 1.9.1
(function() {
  var SampleGame, SamplePlayer, SuperModel, all, defer, uuid,
    bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    hasProp = {}.hasOwnProperty;

  SuperModel = require('spincycle').SuperModel;

  defer = require('node-promise').defer;

  all = require('node-promise').allOrNone;

  uuid = require('node-uuid');

  SamplePlayer = require('./SamplePlayer');

  SampleGame = (function(superClass) {
    extend(SampleGame, superClass);

    SampleGame.type = 'SampleGame';

    SampleGame.model = [
      {
        name: 'players',
        "public": true,
        array: true,
        type: 'SamplePlayer',
        ids: 'players'
      }, {
        name: 'name',
        "public": true,
        value: 'name',
        "default": 'game_' + uuid.v4()
      }
    ];

    function SampleGame(record) {
      this.record = record;
      this.createPlayers = bind(this.createPlayers, this);
      this.postCreate = bind(this.postCreate, this);
      return SampleGame.__super__.constructor.apply(this, arguments);
    }

    SampleGame.prototype.postCreate = function(q) {
      if (this.players.length === 0) {
        return this.createPlayers().then((function(_this) {
          return function() {
            return q.resolve(_this);
          };
        })(this));
      } else {
        return q.resolve(this);
      }
    };

    SampleGame.prototype.createPlayers = function() {
      var q;
      console.log('creating sample players');
      q = defer();
      this.players = [];
      all([new SamplePlayer(), new SamplePlayer()]).then((function(_this) {
        return function(results) {
          console.log('sample players created');
          results.forEach(function(player) {
            console.dir(player);
            _this.players[player.name] = player;
            player.serialize();
            return console.log('  serializing player ' + player.name);
          });
          return q.resolve();
        };
      })(this));
      return q;
    };

    return SampleGame;

  })(SuperModel);

  module.exports = SampleGame;

}).call(this);

//# sourceMappingURL=SampleGame.js.map
