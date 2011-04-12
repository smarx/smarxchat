Code Powering chat.smarx.com
============================

This is the code powering my chat room ([chat.smarx.com](http://chat.smarx.com)).

To use it yourself, you'll need to provide a `src/secrets.coffee` file. Take a look at `src/secrets.coffee.example`.

This code is written in coffeescript. `npm install coffee-script` and then `node /usr/bin/coffee -o . src/*.coffee` should compile everything (even on Windows).

Other dependencies are specified in npm style via `package.json`.

Specify the port number on the commandline, like `app.js -p 8080`.