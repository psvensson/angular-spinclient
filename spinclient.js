// Generated by CoffeeScript 1.9.1
(function() {
  angular.module('angular-spinclient', ['uuid4', 'ngWebSocket', 'ngMaterial']).factory('ngSpinClient', function(uuid4, $websocket, $q) {
    var service;
    service = {
      subscribers: [],
      objsubscribers: [],
      outstandingMessages: [],
      io: io('ws://localhost:3003'),
      registerListener: function(detail) {
        var subscribers;
        subscribers = service.subscribers[detail.message] || [];
        subscribers.push(detail.callback);
        service.subscribers[detail.message] = subscribers;
      },
      registerObjectSubscriber: function(detail) {
        var d, subscribers;
        console.dir(detail);
        d = $q.defer();
        console.log('message-router registering subscriber for object ' + detail.id + ' type ' + detail.type);
        subscribers = service.objsubscribers[detail.id] || [];
        subscribers.push(detail.cb);
        service.objsubscribers[detail.id] = subscribers;
        service.emitMessage({
          target: 'registerForUpdatesOn',
          messageId: uuid4.generate(),
          obj: {
            id: detail.id,
            type: detail.type
          }
        }).then(function(reply) {
          return d.resolve(reply);
        });
        return d.promise;
      },
      emitMessage: function(detail) {
        var d;
        console.log('emitMessage called');
        console.dir(detail);
        d = $q.defer();
        detail.messageId = uuid4.generate();
        service.outstandingMessages.push(detail);
        service.io.emit('message', JSON.stringify(detail));
        detail.d = d;
        return d.promise;
      },
      listTargets: function() {
        var d;
        d = $q.defer();
        service.emitMessage({
          target: 'listcommands'
        }).then(function(targets) {
          return d.resolve(targets);
        });
        return d.promise;
      }
    };
    service.subscribers['OBJECT_UPDATE'] = [
      function(obj) {
        var subscribers;
        console.log('+++++++++++ obj update message router got obj');
        subscribers = service.objsubscribers[obj.id] || [];
        if (subscribers.length === 0) {
          console.log('* OH NOES! * No subscribers for object update on object ' + obj.id);
          return console.dir(service.objsubscribers);
        } else {
          return subscribers.forEach(function(subscriber) {
            return subscriber(obj);
          });
        }
      }
    ];
    service.io.on('message', function(reply) {
      var detail, i, index, info, message, status, subscribers;
      status = reply.status;
      message = reply.payload;
      info = reply.info;
      console.log('got reply id ' + reply.messageId + ' status ' + status + ', info ' + info + ' data ' + message);
      console.dir(reply);
      index = -1;
      if (reply.messageId) {
        i = 0;
        while (i < service.outstandingMessages.length) {
          detail = service.outstandingMessages[i];
          if (detail.messageId === reply.messageId) {
            if (reply.status === 'FAILURE') {
              detail.d.reject(reply);
            } else {
              detail.d.resolve(message);
              index = i;
              break;
            }
          }
          i++;
        }
        if (index > 0) {
          service.outstandingMessages.splice(index, 1);
        }
      } else {
        subscribers = service.subscribers[info];
        if (subscribers) {
          subscribers.forEach(function(listener) {
            listener(message);
          });
        } else {
          console.log('no subscribers for message ' + message);
          console.dir(reply);
        }
      }
    });
    return service;
  }).directive('alltargets', [
    'ngSpinClient', function(client) {
      return {
        restrict: 'AE',
        replace: true,
        templateUrl: 'alltargets.html',
        link: function(scope, elem, attrs) {},
        controller: function($scope) {
          var failure, success;
          $scope.results = [];
          console.log('alltargets controller');
          $scope.onitemselect = (function(_this) {
            return function(item) {
              console.log('alltargets item selected ' + item.id);
              return $scope.itemselected = item;
            };
          })(this);
          client.listTargets().then(function(_targets) {
            var k, results1, v;
            $scope.targets = [];
            results1 = [];
            for (k in _targets) {
              v = _targets[k];
              results1.push($scope.targets.push({
                name: k,
                args: v
              }));
            }
            return results1;
          });
          success = function(results) {
            $scope.results = results;
            return console.dir($scope.results);
          };
          failure = function(reply) {
            console.log('failure' + reply);
            return $scope.status = reply.status + ' - ' + reply.info;
          };
          return $scope.callTarget = function(t) {
            $scope.status = "";
            console.log('calltarget called with ' + t.name);
            return client.emitMessage({
              target: t.name
            }).then(success, failure);
          };
        }
      };
    }
  ]).directive('spinmodel', [
    'ngSpinClient', function(client) {
      return {
        restrict: 'AE',
        replace: true,
        templateUrl: 'spinmodel.html',
        scope: {
          model: '=model',
          edit: '=edit'
        },
        link: function(scope, elem, attrs) {},
        controller: function($scope) {
          var failure, success;
          $scope.isarray = angular.isArray;
          $scope.$watch('model', function(newval, oldval) {
            var k, ref, ref1, results1, v;
            console.log('model is');
            console.dir($scope.model);
            console.log('edit is ' + $scope.edit);
            $scope.listprops = [];
            if ($scope.model) {
              $scope.listprops.push({
                name: 'id',
                value: $scope.model.id
              });
              delete $scope.model.id;
              ref = $scope.model;
              for (k in ref) {
                v = ref[k];
                console.log('pass 1 ' + k + ' isarray = ' + (angular.isArray(v)));
                if (angular.isArray(v) === false) {
                  console.log('adding model prop ' + k + ' -> ' + v);
                  $scope.listprops.push({
                    name: k,
                    value: v
                  });
                }
              }
              ref1 = $scope.model;
              results1 = [];
              for (k in ref1) {
                v = ref1[k];
                console.log('pass 2 ' + k + ' isarray = ' + (angular.isArray(v)));
                if (angular.isArray(v) === true) {
                  results1.push($scope.listprops.push({
                    name: k,
                    value: v
                  }));
                } else {
                  results1.push(void 0);
                }
              }
              return results1;
            }
          });
          success = (function(_this) {
            return function(result) {
              return console.log('success: ' + result);
            };
          })(this);
          failure = (function(_this) {
            return function(err) {
              return console.log('error: ' + err);
            };
          })(this);
          $scope.onChange = (function(_this) {
            return function(model, prop) {
              console.log('onChange called for');
              console.dir(model);
              console.dir(prop);
              return client.emitMessage({
                target: 'updateObject',
                obj: model
              }).then(success, failure);
            };
          })(this);
          return $scope.addModel = function() {
            return client.emitMessage({
              target: '_create' + $scope.model.type,
              obj: {
                name: 'new ' + $scope.model.type,
                type: $scope.model.type
              }
            }).then(success, failure);
          };
        }
      };
    }
  ]).directive('spinlist', [
    'ngSpinClient', function(client) {
      return {
        restrict: 'AE',
        replace: true,
        templateUrl: 'spinlist.html',
        scope: {
          list: '=list',
          listmodel: '=listmodel',
          onselect: '&'
        },
        link: function(scope, elem, attrs) {
          return scope.onselect = scope.onselect();
        },
        controller: function($scope) {
          console.log('spinlist created. list is ' + $scope.list + ' type is ' + $scope.listmodel);
          $scope.subscriptions = [];
          $scope.objects = [];
          $scope.expandedlist = [];
          $scope.selectItem = (function(_this) {
            return function(item) {
              if ($scope.onselect) {
                return $scope.onselect(item);
              }
            };
          })(this);
          $scope.onSubscribedObject = function(o) {
            var i, j, k, len, model, ref, v;
            console.log('onSubscribedObject called ++++++++++++++++++++++++');
            console.dir(o);
            ref = $scope.list;
            for (i = j = 0, len = ref.length; j < len; i = ++j) {
              model = ref[i];
              if (model.id === o.id) {
                console.log('found match in update for object ' + o.id + ' name ' + o.name);
                for (k in o) {
                  v = o[k];
                  model[k] = v;
                }
              }
            }
            return $scope.$apply();
          };
          console.log('subscribing to list ids..');
          return $scope.list.forEach(function(obj) {
            return client.registerObjectSubscriber({
              id: obj.id,
              type: $scope.listmodel,
              cb: $scope.onSubscribedObject
            }).then(function(listenerid) {
              return $scope.subscriptions.push(listenerid);
            });
          });
        }
      };
    }
  ]);

}).call(this);

//# sourceMappingURL=spinclient.js.map
