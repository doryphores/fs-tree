expect = require("chai").expect

temp = require("temp")
fs = require("fs-extra")
Immutable = require("immutable")
path = require("path")
PathWatcher = require("pathwatcher")

temp.track()

FileTree = require("../lib/main")

describe "FileTree", ->
  beforeEach ->
    @tempDir = temp.mkdirSync("file-tree-directory")
    # A file in the root folder
    fs.outputFileSync("#{@tempDir}/at_root", "")
    # Some files in a folder named 'z'
    fs.outputFileSync("#{@tempDir}/z/file_1", "")
    fs.outputFileSync("#{@tempDir}/z/file_2", "")
    fs.outputFileSync("#{@tempDir}/z/file_3", "")
    # A file in a deep folder
    fs.outputFileSync("#{@tempDir}/d/e/e/p/deep_1", "")
    # A deep empty folder
    fs.mkdirsSync("#{@tempDir}/d/e/e/p/e/r")

    @fileTree = new FileTree(@tempDir)

  afterEach ->
    PathWatcher.closeAllWatchers()

  describe "initializing the tree", ->
    it "emits a 'ready' event when done", (done) ->
      @fileTree.on "ready", done
      @fileTree.build()

  describe "initial build", ->
    beforeEach (done) ->
      @fileTree.on "ready", done
      @fileTree.build()

    it "builds the tree as an immutable map with immutable lists of children", ->
      expect(@fileTree.tree).to.be.an.instanceof(Immutable.Map)
      expect(@fileTree.tree.get("children")).to.be.an.instanceof(Immutable.List)
      expect(@fileTree.tree.getIn(["children", 1])).to.be.an.instanceof(Immutable.Map)
      expect(@fileTree.tree.getIn(["children", 1, "children"])).to.be.an.instanceof(Immutable.List)

    it "creates a root element for the tree", ->
      expect(@fileTree.tree.get("name")).to.eql "root"
      expect(@fileTree.tree.get("path")).to.eql @tempDir

    it "reflects the state of the given directory tree", ->
      expect(@fileTree.findNode("at_root").get("type")).to.equal("file")
      expect(@fileTree.findNode("z").get("children").size).to.equal(3)
      expect(@fileTree.findNode("d/e/e").get("children").size).to.equal(1)
      expect(@fileTree.findNode("d/e/e/p/deep_1").get("type")).to.equal("file")
      expect(@fileTree.findNode("path/not/found")).to.be.undefined

    it "orders the nodes folder first", ->
      tree = @fileTree.tree.toJS()
      expect(node.name for node in tree.children).to.eql ["d", "z", "at_root"]

  describe "reacting to changes", ->
    beforeEach (done) ->
      @fileTree.on "ready", done
      @fileTree.build()

    it "does not react when not watching", (done) ->
      triggered = false
      @fileTree.on "change", -> triggered = true
      fs.outputFile("#{@tempDir}/new_file", "")
      setTimeout (->
        expect(triggered).to.be.false
        done()
      ), 500

    describe "when watching a folder node", ->
      beforeEach ->
        @fileTree.tree.getIn(["children", 1, "watcher"]).start()

      describe "when a new file is added to the node", ->
        it "triggers a 'change' event and passes the updated tree", (done) ->
          previousTree = @fileTree.tree
          @fileTree.on "change", (tree) ->
            expect(tree).to.not.equal(previousTree)
            tree = tree.toJS()
            expect(tree.children[1].children[2].name).to.equal "file_21"
            done()
          fs.outputFile("#{@tempDir}/z/file_21", "")

      describe "when a file is removed", ->
        it "triggers a 'change' event and passes the updated tree", (done) ->
          previousTree = @fileTree.tree
          @fileTree.on "change", (tree) ->
            expect(tree).to.not.equal(previousTree)
            tree = tree.toJS()
            expect(node.name for node in tree.children[1].children).to.eql ["file_1", "file_3"]
            done()
          fs.unlinkSync("#{@tempDir}/z/file_2")

      describe "when a file is renamed", ->
        it "triggers a 'change' event and passes the updated tree", (done) ->
          previousTree = @fileTree.tree
          @fileTree.on "change", (tree) ->
            expect(tree).to.not.equal(previousTree)
            tree = tree.toJS()
            expect(node.name for node in tree.children[1].children).to.eql ["file_1", "file_3", "file_4"]
            done()
          fs.renameSync("#{@tempDir}/z/file_2", "#{@tempDir}/z/file_4")
