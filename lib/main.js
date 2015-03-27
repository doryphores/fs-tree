var EventEmitter = require("events").EventEmitter;
var util = require("util");
var Immutable = require("immutable");
var fs = require("fs");
var path = require("path");
var async = require("async");
var PathWatcher = require("pathwatcher");

var FileTree = module.exports = function (rootPath) {
  this.rootPath = rootPath;
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
      console.log("change at:", address);
      self.reloadNode(address);
      self.emit("change", self.tree);
    });
  }

  return Immutable.Map(node);
};

FileTree.prototype.reloadNode = function (address) {
  var self = this;
  var node = this.tree.getIn(address);

  directoryContents(node.get("path")).forEach(function (n, index) {
    if(!node.get("children").findEntry(function (v) {
      return v.get("name") === n.name;
    })) {
      // New node added
      self.tree = self.tree.updateIn(address.concat("children"), function (c) {
        return c.splice(index, 0, self.makeNode(n, address.concat("children", index)));
      })
    }
  });
};

function directoryContents(dirPath) {
  return fs.readdirSync(dirPath).map(function (filename) {
    var s = fs.statSync(path.join(dirPath, filename));
    return {
      name : filename,
      path : path.join(dirPath, filename),
      type : s.isDirectory() ? "folder" : "file"
    };
  }).sort(nodeCompare)
};

function nodeCompare(a, b) {
  if (a.type == b.type) return a.name.localeCompare(b.name);
  return a.type == "folder" ? -1 : 1;
};


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
