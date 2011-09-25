Code Powering chat.smarx.com
============================

This is the code powering my chat room ([chat.smarx.com](http://chat.smarx.com)). This code has been tested with node.js v0.5.7, including the native Windows executable and the [iisnode](https://github.com/tjanczuk/iisnode) IIS module.

To use it yourself, you'll need to provide a `src/secrets.coffee` file. Take a look at `src/secrets.coffee.example`.

Dependencies are specified in npm style via `package.json`. To install, use `npm install` or `ryppi deps`.

The application is written in coffeescript. To compile, run build.cmd.

Specify the port via the PORT environment variable (as with iisnode) or via the command line, like: `node app.js -p 8000`.