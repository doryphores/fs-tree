chai = require("chai")
expect = chai.expect
sinon = require("sinon")
chai.use(require("sinon-chai"));

temp = require("temp")
fs = require("fs-extra")
Immutable = require("immutable")
path = require("path")
PathWatcher = require("pathwatcher")

temp.track()

timer = null
delay = (t, fn) -> timer = setTimeout(fn, t)

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
    clearTimeout(timer)
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
      expect(@fileTree.tree.get("path")).to.eql ""

    it "reflects the state of the given directory tree", ->
      expect(@fileTree.findNode("at_root").get("type")).to.equal("file")
      expect(@fileTree.findNode("z").get("children").size).to.equal(3)
      expect(@fileTree.findNode("d/e/e").get("children").size).to.equal(1)
      expect(@fileTree.findNode("d/e/e/p/deep_1").get("type")).to.equal("file")
      expect(=> @fileTree.findNode("path/not/found")).to.throw "Node not found at path: path/not/found"

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
      delay 500, ->
        expect(triggered).to.be.false
        done()

    describe "when watching a folder node", ->
      beforeEach ->
        @fileTree.watchNode("z")

      it "sets up a path watcher", ->
        expect(@fileTree.watchers).to.have.key("z")

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

        it "the deleted node is no longer available", (done) ->
          previousTree = @fileTree.tree
          @fileTree.on "change", (tree) =>
            expect(=> @fileTree.findNode("z/file_2")).to.throw "Node not found at path: z/file_2"
            done()
          fs.unlinkSync("#{@tempDir}/z/file_2")

        it "siblings of deleted node are re-indexed", (done) ->
          file_3 = @fileTree.findNode("z/file_3")
          @fileTree.on "change", (tree) =>
            expect(@fileTree.findNode("z/file_3")).to.equal file_3
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

      describe "when a watched folder is removed", ->
        it "closes and removes any watchers open on itself or any of its sub folders", (done) ->
          @fileTree.watchNode("d/e")
          @fileTree.watchNode("d/e/e")
          @fileTree.watchNode("d/e/e/p/e/r")
          watcher1 = @fileTree.watchers["d/e/e"]
          watcher2 = @fileTree.watchers["d/e/e/p/e/r"]
          sinon.spy(watcher1, "close")
          sinon.spy(watcher2, "close")
          @fileTree.on "change", ->
            expect(watcher1.close).to.have.been.called
            expect(watcher2.close).to.have.been.called
            expect(@watchers).to.not.have.keys("d/e/e", "d/e/e/p/e/r")
            done()
          fs.removeSync("#{@tempDir}/d/e/e")
