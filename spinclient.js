// Generated by CoffeeScript 1.8.0
(function() {
  angular.module('ngSpinclient', ['uuid4', 'ngMaterial']).factory('spinclient', function(uuid4, $q) {
    var service;
    service = {
      subscribers: [],
      objsubscribers: [],
      outstandingMessages: [],
      modelcache: [],
      io: io('ws://evothings.com:1009'),
      registerListener: function(detail) {
        var subscribers;
        subscribers = service.subscribers[detail.message] || [];
        subscribers.push(detail.callback);
        return service.subscribers[detail.message] = subscribers;
      },
      registerObjectSubscriber: function(detail) {
        var d, subscribers;
        d = $q.defer();
        subscribers = service.objsubscribers[detail.id] || [];
        service.emitMessage({
          target: 'registerForUpdatesOn',
          messageId: uuid4.generate(),
          obj: {
            id: detail.id,
            type: detail.type
          }
        }).then(function(reply) {
          subscribers[reply] = detail.cb;
          service.objsubscribers[detail.id] = subscribers;
          return d.resolve(reply);
        });
        return d.promise;
      },
      deRegisterObjectSubscriber: (function(_this) {
        return function(sid, o) {
          var subscribers;
          subscribers = service.objsubscribers[o.id] || [];
          if (subscribers && subscribers[sid]) {
            delete subscribers[sid];
            service.objsubscribers[o.id] = subscribers;
            return service.emitMessage({
              target: 'deRegisterForUpdatesOn',
              id: o.id,
              type: o.type,
              listenerid: sid
            }).then(function(reply) {});
          }
        };
      })(this),
      emitMessage: function(detail) {
        var d;
        d = $q.defer();
        detail.messageId = uuid4.generate();
        service.outstandingMessages.push(detail);
        service.io.emit('message', JSON.stringify(detail));
        detail.d = d;
        return d.promise;
      },
      getModelFor: function(type) {
        var d;
        d = $q.defer();
        if (service.modelcache[type]) {
          d.resolve(service.modelcache[type]);
        } else {
          service.emitMessage({
            target: 'getModelFor',
            modelname: type
          }).then(function(model) {
            service.modelcache[type] = model;
            return d.resolve(model);
          });
        }
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
      },
      flattenModel: function(model) {
        var k, rv, v;
        rv = {};
        for (k in model) {
          v = model[k];
          if (angular.isArray(v)) {
            rv[k] = v.map(function(e) {
              return e.id;
            });
          } else {
            rv[k] = v;
          }
        }
        return rv;
      }
    };
    service.subscribers['OBJECT_UPDATE'] = [
      function(obj) {
        var k, subscribers, v, _results;
        console.log('+++++++++++ obj update message router got obj');
        subscribers = service.objsubscribers[obj.id] || [];
        _results = [];
        for (k in subscribers) {
          v = subscribers[k];
          _results.push(v(obj));
        }
        return _results;
      }
    ];
    service.io.on('message', function(reply) {
      var detail, i, index, info, message, status, subscribers;
      status = reply.status;
      message = reply.payload;
      info = reply.info;
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
    'spinclient', function(client) {
      return {
        restrict: 'AE',
        replace: true,
        template: '<div> <h2>Status: {{status}}</h2> Return Type:<md-select ng-model="currentmodeltype" placeholder="Select a return type for calls"> <md-option ng-value="opt" ng-repeat="opt in modeltypes">{{ opt }}</md-option> </md-select> <div layout="row"> <div flex> <div ng-repeat="target in targets"> <button ng-click="callTarget(target)">{{target.name}}</button> - <span ng-if="target.args==\'<none>\'">{{target.args}}</span><span ng-if="target.args!=\'<none>\'"><input type="text" ng-model="target.args"></span> </div> </div> <div flex> <spinlist ng-if="results && results.length > 0" list="results" listmodel="currentmodeltype" edit="\'true\'" onselect="onitemselect" style="height:300px;overflow:auto"></spinlist> <md-divider></md-divider> <div ng-if="itemselected"> <spinwalker model="itemselected" edit="\'true\'"></spinwalker> </div> </div> </div> </div>',
        link: function(scope, elem, attrs) {},
        controller: function($scope) {
          var failure, success;
          $scope.results = [];
          console.log('alltargets controller');
          $scope.onitemselect = (function(_this) {
            return function(item) {
              console.log('alltargets item selected ' + item.name);
              return $scope.itemselected = item;
            };
          })(this);
          client.listTargets().then(function(_targets) {
            var k, v, _results;
            $scope.targets = [];
            _results = [];
            for (k in _targets) {
              v = _targets[k];
              _results.push($scope.targets.push({
                name: k,
                argnames: v,
                args: v
              }));
            }
            return _results;
          });
          success = function(results) {
            $scope.results = results;
            return console.dir($scope.results);
          };
          failure = function(reply) {
            console.log('failure' + reply);
            return $scope.status = reply.status + ' - ' + reply.info;
          };
          $scope.callTarget = function(t) {
            var callobj, i, values;
            $scope.status = "";
            console.log('calltarget called with ' + t.name);
            callobj = {
              target: t.name
            };
            if (t.argnames !== "<none>") {
              values = t.args.split(',');
              i = 0;
              t.argnames.split(',').forEach(function(arg) {
                return callobj[arg] = values[i++];
              });
            }
            return client.emitMessage(callobj).then(success, failure);
          };
          return client.emitMessage({
            target: 'listTypes'
          }).then(function(types) {
            return $scope.modeltypes = types;
          });
        }
      };
    }
  ]).directive('spinmodel', [
    'spinclient', function(client) {
      return {
        restrict: 'AE',
        replace: true,
        template: '<div> <md-list > <md-subheader class="md-no-sticky" style="background-color:#ddd"> <md-icon md-svg-src="images/ic_folder_shared_24px.svg" ></md-icon> SpinCycle Model {{model.type}}</md-subheader> <md-list-item ng-repeat="prop in listprops" > <div class="md-list-item-text" layout="row"> <div flex style="background-color:#eee;margin-bottom:2px"> {{prop.name}} </div> <span flex ng-if="prop.type && prop.value && !prop.hashtable"> <md-button ng-click="enterDirectReference(prop)">{{prop.name}}</md-button> > </span> <div ng-if="!prop.array && !prop.type" flex class="md-secondary"> <span ng-if="edit && prop.name != \'id\'"><input type="text" ng-model="model[prop.name]" ng-change="onChange(model, prop.name)"></span> <span ng-if="!edit || prop.name == \'id\'">{{prop.value}}</span> </div> <div flex ng-if="edit && prop.array"> <div><md-button class="md-raised" ng-click="addModel(prop.type, prop.name)">New {{prop.type}}</md-button></div> <spinlist  flex class="md-secondary" listmodel="prop.type" edit="edit" list="prop.value" onselect="onselect" ondelete="ondelete"></spinlist> </div> <span flex ng-if="!edit && prop.array"> <spinlist flex class="md-secondary" listmodel="prop.name" list="prop.value" onselect="onselect"></spinlist> </span> <div flex ng-if="prop.hashtable"> <div ng-if="edit"><md-button class="md-raised" ng-click="addModel(prop.type, prop.name)">New {{prop.type}}</md-button></div> <spinhash flex class="md-secondary" listmodel="prop.type" list="prop.value" onselect="onselect"></spinhash> </div> </div> </md-list-item> </md-list> </div>',
        scope: {
          model: '=model',
          edit: '=edit',
          onselect: '&'
        },
        link: function(scope, elem, attrs) {
          return scope.onselect = scope.onselect();
        },
        controller: function($scope) {
          var failure, success;
          $scope.isarray = angular.isArray;
          $scope.subscriptions = [];
          $scope.onSubscribedObject = function(o) {
            return $scope.model = o;
          };
          if ($scope.model) {
            client.registerObjectSubscriber({
              id: $scope.model.id,
              type: $scope.model.type,
              cb: $scope.onSubscribedObject
            }).then(function(listenerid) {
              return $scope.subscriptions.push({
                sid: listenerid,
                o: $scope.model
              });
            });
          }
          $scope.$watch('model', function(newval, oldval) {
            console.log('spinmodel watch fired for ' + newval.name);
            return $scope.renderModel();
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
              return client.emitMessage({
                target: 'updateObject',
                obj: model
              }).then(success, failure);
            };
          })(this);
          $scope.ondelete = function(item) {
            return client.getModelFor($scope.model.type).then(function(md) {
              var i, list, mid, propname, _i, _len;
              propname = null;
              md.forEach(function(m) {
                if (m.type === item.type) {
                  return propname = m.name;
                }
              });
              list = $scope.model[propname];
              for (i = _i = 0, _len = list.length; _i < _len; i = ++_i) {
                mid = list[i];
                if (mid === item.id) {
                  list.splice(i, 1);
                }
              }
              console.log('updating parent model to list with spliced list');
              return client.emitMessage({
                target: 'updateObject',
                obj: $scope.model
              }).then(function() {
                return client.emitMessage({
                  target: '_delete' + item.type,
                  obj: {
                    id: mid,
                    type: item.type
                  }
                }).then((function(_this) {
                  return function(o) {
                    return console.log('deleted ' + item.type + ' on server');
                  };
                })(this));
              }, failure);
            });
          };
          $scope.renderModel = (function(_this) {
            return function() {
              console.log('spinmodel::renderModel called for ' + $scope.model.name);
              console.dir($scope.model);
              $scope.listprops = [];
              return client.getModelFor($scope.model.type).then(function(md) {
                var foo, i, modeldef, prop, _i, _len, _results;
                modeldef = {};
                md.forEach(function(modelprop) {
                  return modeldef[modelprop.name] = modelprop;
                });
                if ($scope.model) {
                  console.log('making listprops for model');
                  console.dir(md);
                  $scope.listprops.push({
                    name: 'id',
                    value: $scope.model.id
                  });
                  _results = [];
                  for (i = _i = 0, _len = md.length; _i < _len; i = ++_i) {
                    prop = md[i];
                    if (prop.name !== 'id') {
                      foo = {
                        name: prop.name,
                        value: $scope.model[prop.name] || "",
                        type: modeldef[prop.name].type,
                        array: modeldef[prop.name].array,
                        hashtable: modeldef[prop.name].hashtable
                      };
                      _results.push($scope.listprops.push(foo));
                    } else {
                      _results.push(void 0);
                    }
                  }
                  return _results;
                }
              });
            };
          })(this);
          $scope.enterDirectReference = (function(_this) {
            return function(prop) {
              console.log('enterDirectReference called for ');
              console.dir(prop);
              return client.emitMessage({
                target: '_get' + prop.type,
                obj: {
                  id: $scope.model[prop.name],
                  type: prop.type
                }
              }).then(function(o) {
                console.log('enterDirectReference got back ');
                console.dir(o);
                return $scope.onselect(o);
              }, failure);
            };
          })(this);
          $scope.addModel = function(type, propname) {
            console.log('addModel called for type ' + type);
            return client.emitMessage({
              target: '_create' + type,
              obj: {
                name: 'new ' + type,
                type: type
              }
            }).then((function(_this) {
              return function(o) {
                $scope.model[propname].push(o.id);
                console.log('parent model is now');
                console.dir($scope.model);
                return client.emitMessage({
                  target: 'updateObject',
                  obj: $scope.model
                }).then(success, failure);
              };
            })(this), failure);
          };
          return $scope.$on('$destroy', (function(_this) {
            return function() {
              console.log('spinmodel captured $destroy event');
              return $scope.subscriptions.forEach(function(s) {
                return client.deRegisterObjectSubscriber(s.sid, s.o);
              });
            };
          })(this));
        }
      };
    }
  ]).directive('spinwalker', [
    'spinclient', function(client) {
      return {
        restrict: 'AE',
        replace: true,
        template: '<div> <span ng-repeat="crumb in breadcrumbs"> <md-button ng-click="crumbClicked(crumb)">{{crumbPresentation(crumb)}}</md-button> > </span> <md-divider></md-divider> <spinmodel model="selectedmodel" edit="edit" onselect="onselect" style="height:400px;overflow:auto"></spinmodel> </div>',
        scope: {
          model: '=model',
          edit: '=edit'
        },
        link: function(scope, elem, attrs) {},
        controller: function($scope) {
          $scope.selectedmodel = $scope.model;
          $scope.breadcrumbs = [$scope.model];
          $scope.$watch('model', function(newval, oldval) {
            $scope.breadcrumbs = [$scope.model];
            return $scope.selectedmodel = newval;
          });
          $scope.crumbClicked = function(model) {
            var crumb, i, idx, _i, _len, _ref;
            $scope.selectedmodel = model;
            idx = -1;
            _ref = $scope.breadcrumbs;
            for (i = _i = 0, _len = _ref.length; _i < _len; i = ++_i) {
              crumb = _ref[i];
              if (crumb.id = model.id) {
                idx = i;
              }
            }
            console.log('crumbClicked crumbs length = ' + $scope.breadcrumbs.length);
            if (idx > -1 && $scope.breadcrumbs.length > 1) {
              return $scope.breadcrumbs.splice(idx, 1);
            }
          };
          $scope.onselect = function(model, replace) {
            console.log('spinwalker onselect for model ' + model.name);
            console.log(model);
            if (replace) {
              $scope.breadcrumbs = [];
            }
            $scope.selectedmodel = model;
            return $scope.breadcrumbs.push(model);
          };
          return $scope.crumbPresentation = (function(_this) {
            return function(crumb) {
              return crumb.name || crumb.type;
            };
          })(this);
        }
      };
    }
  ]).directive('spinlist', [
    'spinclient', function(client) {
      return {
        restrict: 'AE',
        replace: true,
        template: '<div> <md-list > <md-subheader class="md-no-sticky" style="background-color:#ddd"> <md-icon md-svg-src="images/ic_apps_24px.svg" ></md-icon> SpinCycle List of {{listmodel}}s</md-subheader> <md-list-item ng-repeat="item in expandedlist" > <div class="md-list-item-text" layout="row"> <span flex > <md-button ng-if="!edit" aria-label="delete" class="md-icon-button" ng-click="deleteItem(item)"> <md-icon md-svg-src="images/ic_delete_24px.svg"></md-icon> </md-button> <md-button  ng-click="selectItem(item, true)">{{ item.name }}</md-button> </span> <!-- <span flex class="md-secondary"> {{item.id}}</span> --> </div> </md-list-item> </md-list> </div>',
        scope: {
          list: '=list',
          listmodel: '=listmodel',
          onselect: '&',
          ondelete: '&'
        },
        link: function(scope, elem, attrs) {
          scope.onselect = scope.onselect();
          return scope.ondelete = scope.ondelete();
        },
        controller: function($scope) {
          var failure, model, success, _i, _len, _ref;
          console.log('spinlist created. list is ' + $scope.list.length + ' items, type is ' + $scope.listmodel);
          $scope.subscriptions = [];
          $scope.objects = [];
          $scope.expandedlist = [];
          success = (function(_this) {
            return function(result) {
              return console.log('success: ' + result);
            };
          })(this);
          failure = (function(_this) {
            return function(err) {
              console.log('error: ' + err);
              return console.dir(err);
            };
          })(this);
          $scope.selectItem = (function(_this) {
            return function(item, replace) {
              if ($scope.onselect) {
                return $scope.onselect(item, replace);
              }
            };
          })(this);
          $scope.deleteItem = function(item) {
            if ($scope.ondelete) {
              return $scope.ondelete(item);
            }
          };
          _ref = $scope.list;
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            model = _ref[_i];
            client.emitMessage({
              target: '_get' + $scope.listmodel,
              obj: {
                id: model.id,
                type: $scope.listmodel
              }
            }).then(function(o) {
              var i, mod, _j, _len1, _ref1, _results;
              _ref1 = $scope.list;
              _results = [];
              for (i = _j = 0, _len1 = _ref1.length; _j < _len1; i = ++_j) {
                mod = _ref1[i];
                if (mod.id === o.id) {
                  _results.push($scope.expandedlist[i] = o);
                } else {
                  _results.push(void 0);
                }
              }
              return _results;
            }, failure);
          }
          $scope.onSubscribedObject = function(o) {
            var added, i, k, mod, v, _j, _len1, _ref1;
            console.log('onSubscribedObject called ++++++++++++++++++++++++');
            console.dir(o);
            added = false;
            _ref1 = $scope.list;
            for (i = _j = 0, _len1 = _ref1.length; _j < _len1; i = ++_j) {
              model = _ref1[i];
              if (model.id === o.id) {
                console.log('found match in update for object ' + o.id + ' name ' + o.name);
                mod = $scope.expandedlist[i];
                for (k in o) {
                  v = o[k];
                  added = true;
                  mod[k] = v;
                }
              }
            }
            if (!added) {
              $scope.expandedlist.push(o);
            }
            return $scope.$apply();
          };
          $scope.list.forEach(function(model) {
            if (model.id) {
              return client.registerObjectSubscriber({
                id: model.id,
                type: $scope.listmodel,
                cb: $scope.onSubscribedObject
              }).then(function(listenerid) {
                return $scope.subscriptions.push({
                  sid: listenerid,
                  o: {
                    type: $scope.listmodel,
                    id: model.id
                  }
                });
              });
            }
          });
          return $scope.$on('$destroy', (function(_this) {
            return function() {
              console.log('spinlist captured $destroy event');
              return $scope.subscriptions.forEach(function(s) {
                return client.deRegisterObjectSubscriber(s.sid, s.o);
              });
            };
          })(this));
        }
      };
    }
  ]).directive('spinhash', [
    'spinclient', function(client) {
      return {
        restrict: 'AE',
        replace: true,
        template: '<div> <md-list> <md-list-item ng-repeat="item in expandedlist" > <div class="md-list-item-text" layout="row"> <md-button ng-if="!edit" aria-label="delete" class="md-icon-button" ng-click="deleteItem(item)"> <md-icon md-svg-src="bower_components/material-design-icons/action/svg/production/ic_delete_24px.svg"></md-icon> </md-button> <md-button  ng-click="selectItem(item)">{{ item.name }}</md-button> </div> </md-list> </div>',
        scope: {
          list: '=list',
          listmodel: '=listmodel',
          onselect: '&',
          ondelete: '&'
        },
        link: function(scope, elem, attrs) {
          return scope.onselect = scope.onselect();
        },
        controller: function($scope) {
          var failure, mid, _i, _len, _ref;
          console.log('spinhash list for model ' + $scope.listmodel + ' is');
          console.dir($scope.list);
          $scope.expandedlist = [];
          failure = (function(_this) {
            return function(err) {
              console.log('error: ' + err);
              return console.dir(err);
            };
          })(this);
          _ref = $scope.list;
          for (_i = 0, _len = _ref.length; _i < _len; _i++) {
            mid = _ref[_i];
            client.emitMessage({
              target: '_get' + $scope.listmodel,
              obj: {
                id: mid,
                type: $scope.listmodel
              }
            }).then(function(o) {
              var i, modid, _j, _len1, _ref1, _results;
              _ref1 = $scope.list;
              _results = [];
              for (i = _j = 0, _len1 = _ref1.length; _j < _len1; i = ++_j) {
                modid = _ref1[i];
                if (modid === o.id) {
                  console.log('adding hashtable element ' + o.name);
                  _results.push($scope.expandedlist[i] = o);
                } else {
                  _results.push(void 0);
                }
              }
              return _results;
            }, failure);
          }
          return $scope.selectItem = (function(_this) {
            return function(item, replace) {
              if ($scope.onselect) {
                return $scope.onselect(item, replace);
              }
            };
          })(this);
        }
      };
    }
  ]);

}).call(this);

//# sourceMappingURL=spinclient.js.map
