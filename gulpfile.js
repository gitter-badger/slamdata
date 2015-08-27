"use strict";

var gulp = require("gulp"),
    header = require("gulp-header"),
    contentFilter = require("gulp-content-filter"),
    purescript = require("gulp-purescript"),
    less = require("gulp-less"),
    webpack = require("webpack-stream"),
    run = require("gulp-run"),
    rimraf = require("rimraf"),
    fs = require("fs");

var slamDataSources = [
  "src/**/*.purs",
  "test/src/**/*.purs"
];

var vendorSources = [
  "bower_components/purescript-*/src/**/*.purs",
];

var sources = slamDataSources.concat(vendorSources);

var foreigns = [
  "src/**/*.js",
  "bower_components/purescript-*/src/**/*.js",
  "test/src/**/*.js"
];

gulp.task("clean", function () {
  ["output", "tmp", "public/js/file.js", "public/js/notebook.js", "public/css/main.css"].forEach(function (path) {
    rimraf.sync(path);
  });
});

gulp.task("make", function() {
  return purescript.psc({
    src: sources,
    ffi: foreigns
  });
});

gulp.task("add-headers", function () {
  // read in the license header
  var licenseHeader = "{-\n" + fs.readFileSync('LICENSE.header', 'utf8') + "-}\n\n";

  // filter out files that already have a license header
  var contentFilterParams = { include: /^(?!\{-\nCopyright)/ };

  // prepend license header to all source files
  return gulp.src(slamDataSources, {base: "./"})
            .pipe(contentFilter(contentFilterParams))
            .pipe(header(licenseHeader))
            .pipe(gulp.dest("./"));
});

var bundleTasks = [];

var mkBundleTask = function (name, main) {

  gulp.task("prebundle-" + name, ["make"], function() {
    return purescript.pscBundle({
      src: "output/**/*.js",
      output: "tmp/js/" + name + ".js",
      module: main,
      main: main
    });
  });

  gulp.task("bundle-" + name, ["prebundle-" + name], function () {
    return gulp.src("tmp/js/" + name + ".js")
      .pipe(webpack({
        resolve: { modulesDirectories: ["node_modules"] },
        output: { filename: name + ".js" }
      }))
      .pipe(gulp.dest("public/js"));
  });

  return "bundle-" + name;
};

gulp.task("bundle", [
  mkBundleTask("file", "Entries.File"),
  mkBundleTask("notebook", "Entries.Notebook")
]);


var fastBundleTask = function(name, main) {
    gulp.task("make-entry-" + name, ["make"], function(cb) {
        var command = "require(\"" + main + "\").main();";
        fs.writeFile("tmp/js/entries/" + name + ".js", command, cb);
    });
    gulp.task("fast-bundle-" + name, ["make-entry-" + name], function() {
        gulp.src("tmp/js/entries/" + name + ".js")
            .pipe(webpack({
                output: { filename: name + ".js" },
                resolve: { modulesDirectories: ["node_modules", "output"] }
            }))
            .pipe(gulp.dest("public/js"));
    });
    return "fast-bundle-" + name;
};

gulp.task("fast-bundle", [
    fastBundleTask("file", "Entries.File"),
    fastBundleTask("notebook", "Entries.Notebook")
]);

gulp.task("less", function() {
  return gulp.src(["less/main.less"])
    .pipe(less({ paths: ["less/**/*.less"] }))
    .pipe(gulp.dest("public/css"));
});

// We don't use `mkBundleTask` here as there's no need to `webpack` - this
// bundle as it's going to be running in node anyway
gulp.task("bundle-test", ["bundle", "less"], function() {
  return purescript.pscBundle({
    src: "output/**/*.js",
    output: "tmp/js/test.js",
    module: "Test.Selenium",
    main: "Test.Selenium"
  });
});

gulp.task("test", ["bundle-test"], function() {
  return run("node test", { verbosity: 3 }).exec();
});

gulp.task("remote-test", ["bundle-test"], function() {
  return run("node test --remote", { verbosity: 3 }).exec();
});

var mkWatch = function(name, target, files) {
  gulp.task(name, [target], function() {
    return gulp.watch(files, [target]);
  });
};




var allSources = sources.concat(foreigns);
mkWatch("watch-less", "less", ["less/**/*.less"]);
mkWatch("watch-file", "bundle-file", allSources);
mkWatch("watch-notebook", "bundle-notebook", allSources);
mkWatch("watch-file-fast", "fast-bundle-file", allSources);
mkWatch("watch-notebook-fast", "fast-bundle-notebook", allSources);

gulp.task("watch", ["watch-less", "watch-file", "watch-notebook"]);
gulp.task("dev", ["watch-less", "watch-file-fast", "watch-notebook-fast"]);
gulp.task("default", ["add-headers", "less", "bundle"]);
