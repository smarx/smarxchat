http = require 'http'

class HttpClientPool
	constructor: () -> @clients = {}
	
	request: (port, address, noNagle, errCallback, others...) ->
		key = "#{address}:#{port}"
		if @clients[key]?
			client = undefined
			while @clients[key].length > 0 and not client?
				client = @clients[key].shift()
				if client?.__die
					client.destroy()
					client = undefined
				if client? then break
			until @clients[key].length == 0 or (client? and not client.__die)
				client = @clients[key].shift()
		if not client?
			client = http.createClient port, address
			timeout = new Date().getTime() + 30000
			client.setNoDelay noNagle
			client.on 'error', errCallback if errCallback?
			client.on 'error', (error) =>
				if @clients[key]?
					delete c for c in @clients[key] when c == client
					delete @clients[key] if @clients[key].length == 0
				client.destroy()
				#throw error if error.errno != process.ECONNRESET and error.errno != process.EPERM
			client.on 'close', () =>
				if @clients[key]?
					delete c for c in @clients[key] when c == client
					delete @clients[key] if @clients[key].length == 0
				client.destroy()
		client.__timeout = timeout
		setTimeout () ->
			if client.__timeout == timeout
				client.__die = true
		, 30000
		req = client.request others...
		req.on 'response', (response) =>
			response.on 'end', () =>
				client.removeListener 'error', errCallback if errCallback?
				@clients[key] = [] if not @clients[key]?
				@clients[key].push client

exports.HttpClientPool = HttpClientPool