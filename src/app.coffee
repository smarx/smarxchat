require.paths.push '.'
wastorage = require 'wastorage'
express = require 'express'
util = require 'util'
OAuth = require('oauth').OAuth
url = require 'url'
http = require 'http'
fs = require 'fs'
secrets = require 'secrets'

maxtime = 315360000000000
pad = (n) ->
	len = 15
	s = n.toString()
	if s.length < len
		s = ('000000000000000' + s).slice(-len)
	return s

tables = new wastorage.TableStorage secrets.StorageAccount, secrets.StorageKey

#tables.proxyServer = '127.0.0.1'
#tables.proxyPort = 8888

tables.createTable name for name in ['ChatMessages', 'Tokens', 'Users', 'Logs']
log = (message) ->
	console.log message
	tables.insert 'Logs', {
		'PartitionKey': ''
		'RowKey': pad(maxtime - new Date().getTime()) + "_" + process.pid + "_" + Math.floor(Math.random()*100)
		'Message': message
	}
log "hello #{process.pid} - #{process.env['COMPUTERNAME']}"
log "goodbye #{process.pid}"

###
setInterval () ->
	log "#{process.pid}: #{util.inspect process.memoryUsage()}"
, 1000
###

process.on 'uncaughtException', (err) ->
  log('UNCAUGHT exception: ' + err)
  log err.stack

tables.exceptionHandler = (exception) ->
	log 'client exception'
	log exception.stack

pending = []
lastseen = maxtime - new Date().getTime() + 30000
buffer = []
starttime = new Date().getTime()
n = -1
timeout = undefined
version = 0
check = (v) ->
	return if v != version
	clearTimeout timeout if timeout?
	timeout = setTimeout () ->
		console.log 'restarting'
		v += 1
		version = v
		check(v)
	, 5000
	expiration = new Date().getTime() - 30000
	if pending.length > 0
		for i in [(pending.length-1)..0]
			if pending[i].timestamp < expiration
				pending[i].response.send []
				pending.splice i, 1
	tables.query 'ChatMessages', {'$filter': "PartitionKey eq '' and RowKey lt '#{lastseen}'"}, (messages) ->
		return if v != version
		n += 1
		if n == 100
			log "#{process.pid} - #{new Date().getTime() - starttime} - #{util.inspect process.memoryUsage()}"
			n = 0
			starttime = new Date().getTime()
		if messages.length > 0
			for message in messages
				if message.RowKey >= lastseen
					console.log "ERROR!"
			###
			tables.insert 'ChatMessages', {
				'PartitionKey': '',
				'RowKey': pad(maxtime - new Date().getTime())
				'Message': "I\'m here. #{process.pid}"
				'IsAnnouncement': true
			} for message in messages when message.Message == '/running'
			tables.insert 'ChatMessages', {
				'PartitionKey': '',
				'RowKey': pad(maxtime - new Date().getTime())
				'Message': (util.inspect process.memoryUsage()) + "*** #{process.pid} ***"
				'IsAnnouncement': true
			} for message in messages when message.Message == '/memory'
			###
			lastseen = messages[0].RowKey
			buffer = messages.concat buffer
			buffer.pop() until buffer.length <= 15
			until pending.length == 0
				request = pending.pop()
				if request? and request.timestamp >= expiration
					request.response.send (b for b in buffer when b.RowKey < request.since).reverse()
		setTimeout () ->
			check(v)
		, 50
	, (e) ->
		setTimeout () ->
			check(v)
		, 50
		log e
check(version)

check_logouts = () ->
	tables.query 'Users', {
		'$filter': "PartitionKey eq '' and LastActivity lt datetime'#{JSON.stringify(new Date(new Date().getTime() - 60000))[1...-1]}'"
	}, (oldusers) ->
		for user in oldusers
			tables.delete 'Users', user.PartitionKey, user.RowKey, (response) ->
				if response.statusCode == 204
					tables.insert 'ChatMessages', {
						'PartitionKey': ''
						'RowKey': pad(maxtime - new Date().getTime())
						'Sender': user.RowKey
						'Message': "#{user.RowKey} has left the room"
						'IsAnnouncement': true
						'IsLeaving': true
					}
		setTimeout check_logouts, 5000
	, () ->
		setTimeout check_logouts, 5000
check_logouts()

users = {}
get_username = (token, callback) ->
	if not token? then return callback undefined
	user = users[token]
	if user?
		if new Date().getTime() - user.timestamp < 60000
			return callback user.name
		else
			delete users[token]
	tables.query 'Tokens', {
		'$filter': "PartitionKey eq '#{token}' and RowKey eq ''"
	}, (tokens) ->
		if tokens.length > 0
			users[token] = {
				'timestamp': new Date().getTime()
				'name': tokens[0].ScreenName
			}
			callback tokens[0].ScreenName
		else
			callback undefined

app = express.createServer()
app.configure () ->
	app.use express.bodyParser()
	app.use express.cookieParser()
	app.use app.router
	app.use express.static(__dirname + '/public')
	app.set 'views', __dirname + '/views'
	app.set 'view options', {
			layout: false
	}
	
	app.get '/api', (req, res, next) ->
		res.header 'Cache-Control', 'no-cache'
		get_username req.cookies.token, (username) ->
			if username?
				since = req.query.since or maxtime
				if buffer.length > 0 and buffer[0].RowKey < since
					res.send (b for b in buffer when b.RowKey < since).reverse()
				else
					pending.push { 'response': res, 'since': since, 'timestamp': new Date().getTime() }
				tables.update 'Users', {
					'PartitionKey': ''
					'RowKey': username
					'LastActivity': new Date()
				}, (result) ->
					if result.statusCode == 404
						tables.insert 'Users', {
							'PartitionKey': ''
							'RowKey': username
							'LastActivity': new Date()
						}, (result) ->
							if result.statusCode == 201
								tables.insert 'ChatMessages', {
									'PartitionKey': ''
									'RowKey': pad(maxtime - new Date().getTime())
									'Sender': username
									'Message': "#{username} has joined"
									'IsAnnouncement': true
								}
			else
				res.send 403

	app.post '/api', (req, res, next) ->
		get_username req.cookies.token, (username) ->
			if username?
				message = {
					'PartitionKey': ''
					'RowKey': pad(maxtime - new Date().getTime())
					'Sender': username
					'Message': req.body.message
				}
				if message.Message.substring(0, 4) == "/me "
					message.Message = "#{username} #{message.Message.substring 4}."
					message.IsAnnouncement = true
				else if message.Message.substring(0, 6) == "/slap "
					message.Message = "#{username} slaps #{message.Message.substring 6} around a bit with a large trout."
					message.IsAnnouncement = true
				message.FromAdmin = true if username == 'smarx'
				tables.insert 'ChatMessages', message, () -> res.send 200
			else
				res.send 403

	app.get '/login', (req, res, next) ->
		res.header 'Cache-Control', 'no-cache'
		if req.query.force? and req.cookies.token?
			res.header 'Set-Cookie', "token=nothing; path=/; expires=Wednesday, 09-Nov-99 23:12:40 GMT"
		oa = new OAuth "http://twitter.com/oauth/request_token",
								 "http://twitter.com/oauth/access_token",
                                 secrets.OAuthKey, secrets.OAuthSecret
								 "1.0A", url.format({
										'protocol': 'http'
										'host': req.header('host')
										'pathname': '/callback'
								 }), "HMAC-SHA1"
		oa.getOAuthRequestToken (error, oauth_token, oauth_token_secret, results) ->
			tables.insert 'Tokens', {
				'PartitionKey': oauth_token
				'RowKey': ''
				'Secret': oauth_token_secret
			}, () ->
				query = { 'oauth_token': oauth_token }
				query['force_login'] = 'true' if req.query.force?
				res.send null, {
					'Location': url.format {
						'protocol': 'http'
						'hostname': 'twitter.com'
						'pathname': '/oauth/authenticate'
						'query': query
					}
				}, 302
				
	app.get '/callback', (req, res, next) ->
		oa = new OAuth "http://twitter.com/oauth/request_token",
						 "http://twitter.com/oauth/access_token", 
                         secrets.OAuthKey, secrets.OAuthSecret
						 "1.0A", url.format({
								'protocol': 'http'
								'host': req.header('host')
								'pathname': '/callback'
						 }), "HMAC-SHA1"
		tables.query 'Tokens', {
			'$filter': "PartitionKey eq '#{req.query.oauth_token}' and RowKey eq ''"
		}, (tokens) ->
			if tokens.length > 0
				oa.getOAuthAccessToken req.query.oauth_token, tokens[0].Secret, req.query.oauth_verifier, (error, oauth_token, oauth_token_secret, results) ->
					tables.insert 'Tokens', {
						'PartitionKey': oauth_token
						'RowKey': ''
						'Secret': oauth_token_secret
						'ScreenName': results['screen_name']
					}, () ->
						res.send null, {
							'Location': url.format {
								'protocol': 'http'
								'host': req.header('host')
								'pathname': '/'
							}
							'Set-Cookie': "token=#{oauth_token}; path=/"
						}, 302
					, () ->
						res.writeHead 200, {'Content-Type': 'text/plain'}
						res.end 'ERROR'
			else
				res.send 403

	app.get '/who', (req, res, next) ->
		res.header 'Cache-Control', 'no-cache'
		tables.query 'Users', {
			'$filter': "PartitionKey eq ''"
		}, (users) ->
			res.send (user.RowKey for user in users)

	app.get '/', (req, res, next) ->
		res.header 'Cache-Control', 'no-cache'
		get_username req.cookies.token, (username) ->
			if username?
				res.render 'index.ejs', { 'locals':
					{ 'username': username }
				}
			else
				tables.query 'Users', { 
					'$filter': "PartitionKey eq ''"
				}, (users) ->
					res.render 'welcome.ejs', { 'locals':
						{ 'whostring': (user.RowKey for user in users).join(', ') }
					}

	app.error (err, req, res, next) ->
		log err
		log err.stack

app.listen process.argv[3]