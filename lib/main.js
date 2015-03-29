var EventEmitter = require("events").EventEmitter;
var util = require("util");
var Immutable = require("immutable");
var fs = require("fs");
var path = require("path");
var _ = require("underscore");
var PathWatcher = require("pathwatcher");

var FileTree = module.exports = function (rootPath) {
  this.rootPath = rootPath;
  this.nodeMap = {};
  
  this.emitChange = _.debounce(function () {
    this.emit("change", this.tree);
  }.bind(this), 100);
};

util.inherits(FileTree, EventEmitter);

FileTree.prototype.build = function () {
  this.tree = this.makeNode({
    type : "folder",
    name : "root",
    path : this.rootPath
  }, []);
  this.emit("ready");
};

FileTree.prototype.makeNode = function (node, address) {
  var self = this;
  
  this.nodeMap[node.path] = address;
  
  if (!node.type) {
    var s = fs.statSync(node.path);
    node.type = s.isDirectory() ? "folder" : "file";
  }
  
  if (node.type === "folder") {
    node.children = Immutable.List(
      directoryContents(node.path).map(function (n, index) {
        return self.makeNode(n, address.concat(["children", index]));
      })
    );

    node.watcher = new Watcher(node.path, function (evt) {
      self.reloadNode(address);
      self.emitChange();
    });
  }

  return Immutable.Map(node);
};

FileTree.prototype.reloadNode = function (address) {
  var self = this;
  var node = this.tree.getIn(address);
  var entries = directoryContents(node.get("path"));
  var children = node.get("children");
  
  var updateNode = function (children) {
    return children.filter(function (n) {
      return _.find(entries, {name: n.get("name"), type: n.get("type")});
    });
  };

  entries.forEach(function (n, index) {
    if(!children.findEntry(function (v) {
      return v.get("name") === n.name;
    })) {
      // New node added
      updateNode = _.compose(function (children) {
        return children.splice(index, 0, self.makeNode(n, address.concat("children", index)));
      }, updateNode);
    }
  });
  
  this.tree = this.tree.withMutations(function (tree) {
    return tree.updateIn(address.concat("children"), updateNode);
  });
};

FileTree.prototype.findNode = function (nodePath) {
  var address = this.nodeMap[path.join(this.rootPath, nodePath)];
  return address && this.tree.getIn(address);
};

function directoryContents(dirPath) {
  return fs.readdirSync(dirPath).map(function (filename) {
    var s = fs.statSync(path.join(dirPath, filename));
    return {
      name : filename,
      path : path.join(dirPath, filename),
      type : s.isDirectory() ? "folder" : "file"
    };
  }).sort(function nodeCompare(a, b) {
    if (a.type == b.type) return a.name.localeCompare(b.name);
    return a.type == "folder" ? -1 : 1;
  });
}


var Watcher = function (nodePath, listener) {
  this.nodePath = nodePath;
  this.watching = false;
  this.listener = listener;
};

Watcher.prototype.start = function () {
  if (this.watching) {
    this.stop();
  }
  this.watching = true;
  this.watcher = PathWatcher.watch(this.nodePath, this.listener);
};

Watcher.prototype.stop = function () {
  if (this.watching) {
    this.watching = false;
    this.watcher.close();
  }
};
