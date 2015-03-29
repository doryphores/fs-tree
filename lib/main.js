var EventEmitter = require("events").EventEmitter,
    util         = require("util"),
    Immutable    = require("immutable"),
    fs           = require("fs"),
    path         = require("path"),
    _            = require("underscore"),
    PathWatcher  = require("pathwatcher");

var FileTree = module.exports = function (rootPath) {
  this.rootPath = rootPath;
  this.nodeMap = {};
  this.watchers = {};
  
  this.emitChange = _.debounce(function () {
    this.emit("change", this.tree);
  }.bind(this), 100);
};

util.inherits(FileTree, EventEmitter);

FileTree.prototype.build = function () {
  this.tree = this.makeNode({
    type : "folder",
    name : "root",
    path : ""
  }, []);
  this.emit("ready");
};

FileTree.prototype.makeNode = function (node, address) {
  // Store address for easy node finding
  this.nodeMap[node.path] = address;
  
  // Get node type if unknown
  if (!node.type) {
    node.type = fs.statSync(this.absolute(node.path)).isDirectory() ? "folder" : "file";
  }
  
  if (node.type === "folder") {
    // Create the folder's nodes
    node.children = Immutable.List(
      this.directoryContents(node.path).map(function (n, index) {
        // Pass in the new node's address
        return this.makeNode(n, address.concat(["children", index]));
      }.bind(this))
    );
  }

  // Make it immutable
  return Immutable.Map(node);
};

FileTree.prototype.reloadNode = function (nodePath) {
  var self = this;
  var node = this.findNode(nodePath);
  var address = this.nodeMap[nodePath];
  var children = node.get("children");
  var entries;
  
  try {
    entries = this.directoryContents(nodePath);
  } catch (e) {
    if (e.code === 'ENOENT') {
      // Directory does not exist so do nothing
      return;
    }
  }
  
  var updateNode = function (children) {
    return children.filter(function (n) {
      var found = _.find(entries, {name: n.get("name"), type: n.get("type")});
      // This node has been removed so unwatch its path
      if (!found) self.unwatchNode(n.get("path"));
      return found;
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
  
  this.tree = this.tree.updateIn(address.concat("children"), function(children) {
    return updateNode(children.asMutable()).asImmutable();
  });
};

FileTree.prototype.findNode = function (nodePath) {
  var address = this.nodeMap[nodePath];
  return address && this.tree.getIn(address);
};

FileTree.prototype.watchNode = function (nodePath) {
  if (this.watchers[nodePath]) return;
  
  this.watchers[nodePath] = PathWatcher.watch(this.absolute(nodePath), function (evt) {
    if (evt === "change") {
      this.reloadNode(nodePath);
      this.emitChange();
    }
  }.bind(this));
};

FileTree.prototype.unwatchNode = function (nodePath) {
  this.watchers = _.omit(this.watchers, function (v, watchPath) {
    var match = watchPath.match("^" + nodePath + "(\/|$)");
    if (match) {
      this.watchers[watchPath].close();
    }
    return match;
  }.bind(this));
};

FileTree.prototype.absolute = function (nodePath) {
  return path.join(this.rootPath, nodePath);
}

FileTree.prototype.directoryContents = function (dirPath) {
  var absDirPath = this.absolute(dirPath);
  return fs.readdirSync(absDirPath).map(function (filename) {
    var s = fs.statSync(path.join(absDirPath, filename));
    return {
      name : filename,
      path : path.join(dirPath, filename),
      type : s.isDirectory() ? "folder" : "file"
    };
  }).sort(function nodeCompare(a, b) {
    if (a.type == b.type) return a.name.localeCompare(b.name);
    return a.type == "folder" ? -1 : 1;
  });
};
