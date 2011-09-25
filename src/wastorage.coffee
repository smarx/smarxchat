crypto = require 'crypto'
http = require 'http'
sax = require 'sax'
querystring = require 'querystring'

class TableStorage
	constructor: (@account, @key) ->
	
	_doOperation: (method, path, query, data, callback, errCallback) ->
		data = data or ''
		data = @atomSerialize data if data instanceof Object
		dateString = new Date().toGMTString()
		reqpath = "/#{path}"
		reqpath += "?#{querystring.stringify(query)}" if query?
		headers = {
			 'host': "#{@account}.table.core.windows.net"
			 'Authorization': "SharedKeyLite #{@account}:" + crypto.createHmac('sha256', new Buffer(@key, 'base64').toString('binary')).update(new Buffer("#{dateString}\n/#{@account}/#{path}", 'utf8')).digest('base64')
			 'MaxDataServiceVersion': '2.0;NetFx'
			 'Accept': 'application/atom+xml,application/xml'
			 'Content-Type': 'application/atom+xml'
			 'x-ms-version': '2009-09-19'
			 'x-ms-date': dateString
			 'Content-Length': data.length
			 'Connection': 'Keep-Alive'
		}
		if method.toLowerCase() == 'put' or method.toLowerCase() == 'delete'
			headers['If-Match'] = '*'
		options = {
			host: "#{@account}.table.core.windows.net",
			port: 80,
			path: reqpath,
			method: method,
			headers: headers
		}
		req = http.request options, callback
		if @proxyServer?
			options.host = @proxyServer
			options.port = @proxyPort
		req.setNoDelay true
		req.on 'error', errCallback if errCallback?
		req.end data

	createTable: (table, callback) ->
		@insert 'Tables', { 'TableName': table }, callback
	
	atomSerialize: (o) ->
		ret = '''
			  <?xml version="1.0" encoding="utf-8" standalone="yes"?>
			  <entry xmlns:d="http://schemas.microsoft.com/ado/2007/08/dataservices" xmlns:m="http://schemas.microsoft.com/ado/2007/08/dataservices/metadata" xmlns="http://www.w3.org/2005/Atom">
			  <content type="application/xml">
			      <m:properties>\n
			  '''

		for name, value of o
			switch typeof value
				when 'string'
					type = 'Edm.String'
					value = value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
				when 'boolean' then type = 'Edm.Boolean'
				when 'number'
					type = if Math.round(value) == value then 'Edm.Int64' else 'Edm.Double'
				when 'object'
					if value instanceof Date
						type = 'Edm.DateTime'
						value = JSON.stringify(value)[1...-1]
					else
						continue
				else
						continue
			type = 'Edm.String' if name == 'PartitionKey' or name == 'RowKey'
			ret += "        <d:#{name} m:type=\"#{type}\">#{value}</d:#{name}>\n"

		ret += '''
			       </m:properties>
			   </content>
			   </entry>
			   '''
		return ret

	insert: (table, object, callback, errCallback) ->
		@_doOperation 'POST', table, null, object, callback, errCallback
		
	update: (table, object, callback) ->
		@_doOperation 'PUT', "#{table}(PartitionKey='#{object.PartitionKey}',RowKey='#{object.RowKey}')", null, object, callback

	delete: (table, partitionKey, rowKey, callback) ->
		@_doOperation 'DELETE', "#{table}(PartitionKey='#{partitionKey}',RowKey='#{rowKey}')", null, null, callback
		
	query: (table, queryParams, callback, errCallback) ->
		starttime = new Date().getTime()
		@_doOperation 'GET', "#{table}()", queryParams, null, (response) =>
			if response.statusCode != 200
				if callback? then return errCallback response
				else return
			nextpk = response.headers['x-ms-continuation-nextpartitionkey']
			nextrk = response.headers['x-ms-continuation-nextrowkey']
			response.setEncoding 'utf8'
			parser = sax.parser true
			entities = []
			current_entity = undefined
			current_property = undefined
			current_property_type = undefined
			parser.onerror = (e) ->
				errCallback e
			parser.onopentag = (tag) ->
				if tag.name == 'm:properties'
					entities.push current_entity if current_entity?
					current_entity = {}
				else if tag.name.substring(0, 2) == 'd:'
					current_property = tag.name.substring 2
					current_property_type = tag.attributes['m:type']
					current_entity[current_property] = '' # in case there's no text
			parser.onclosetag = () -> current_property = undefined
			parser.ontext = (t) ->
				if current_property?
					current_entity[current_property] =
						switch current_property_type
							when '' then t or ''
							when 'Edm.DateTime' then JSON.parse "\"#{t}\""
							when 'Edm.Boolean' then t == 'true'
							when 'Edm.Int32' then parseInt t
							when 'Edm.Double' then parseDouble t
							else t
			response.on 'data', (chunk) ->
				parser.write chunk
			response.on 'end', () =>
				parser.close()
				entities.push current_entity if current_entity?
				if nextpk?
					queryParams = queryParams or {}
					queryParams['NextPartitionKey'] = nextpk
					if nextrk?
						queryParams['NextRowKey'] = nextrk
					else
						delete queryParams['NextRowKey']
					@query table, queryParams, (entities2) ->
						callback entities.concat entities2
				else
					callback entities
		, errCallback
					
exports.TableStorage = TableStorage