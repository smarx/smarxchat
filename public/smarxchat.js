function addAnnouncement(message) {
	addMessage({'RowKey': 315360000000000 - new Date().getTime(), 'Message': message, 'IsAnnouncement': true});
}

function pad(n) {
	return ('00' + n.toString()).slice(-2);
}

var users = {};

var hasFocus = true;
var msgCount = 0;
var blinkyTitleInterval = undefined;

function addMessage(message) {
	if (!hasFocus) {
		msgCount += 1;
		if (!blinkyTitleInterval) {
			document.title = '(' + msgCount + ') - chat.smarx';
		}
	}
	var row = $("<tr>");
	var time = new Date(315360000000000 - message.RowKey);
	row.append($("<td>").addClass('time').text('[' + pad(time.getHours()) + ':' + pad(time.getMinutes()) + ']'));
	if (message.Sender) {
		users[message.Sender] = 1;
	}
	if (message.IsLeaving) {
		delete users[message.Sender];
	}
	if (!message.IsAnnouncement) {
		row.append($("<th>").attr('title', message.Sender).text(message.Sender.substring(0,16) + ':'))
		if (message.FromAdmin) {
			row.addClass('admin');
		}
	}
	var td = $("<td>").addClass(message.IsAnnouncement ? 'announcement' : 'statement').text(message.IsAnnouncement ? '*** ' + message.Message + ' ***' : message.Message);
	if (message.Message) {
		var yourname = $("#yourname").text();
		if (td.html().indexOf('@' + yourname) >= 0) {
			td.html(td.html().replace('@' + yourname, '<span class="yourname">@' + yourname + '</span>'));
			if (!hasFocus) {
				blinkyTitleInterval = setInterval(function () {
					if (document.title == '@' + yourname) {
						document.title = '(' + msgCount + ') - chat.smarx';
					} else {
						document.title = '@' + yourname;
					}
				}, 500);
			}
		}
	}
	row.append(td);
	$("#messages").append($("<table>").append($("<tbody>").append(row)));
	$("#messages").attr({ scrollTop: $("#messages").attr("scrollHeight") });
}

var ecount = 0;
function fetch(since) {
	var path = '/api'
	if (since) {
		path += '?since=' + since
	}
	$.ajax({
		url: path,
		dataType: 'json',
		cache: false,
		success: function(data) {
            ecount = 0;
			if (!data || !(data instanceof Array)) {
				setTimeout(function () { fetch(since); }, 5000); addAnnouncement("error, retrying in five seconds...");
				return;
			}
			setTimeout(function () { fetch(data.length > 0 ? data[data.length-1].RowKey : since) });
			for (var i = 0; i < data.length; i++) {
				message = data[i];
				addMessage(message);
			}
		},
		error: function() {
			setTimeout(function () { fetch(since); }, 5000);
            if (++ecount > 1) {
                addAnnouncement("error, retrying in five seconds...");
            }
		},
		timeout: 45000
	});
}

$(function () {
	$('#themetoggle').click(function() {
		if ($('#theme').attr('href') == '/themes/retro.css') {
			$('#theme').attr('href', '/themes/white.css');
		} else {
			$('#theme').attr('href', '/themes/retro.css');
		}
		return false;
	});
	$("#messages").mousewheel(function (event, delta) {
		if (delta > 0) {
			$('#messages').attr('scrollTop', $('#messages').attr('scrollTop') - 50);
		}
		else {
			$('#messages').attr('scrollTop', $('#messages').attr('scrollTop') + 50);
		}
		return false;
	});
	$(document).keydown(function (event) {
		if (event.target.id != 'message') {
			if (event.keyCode == 35) {
				$('#messages').attr('scrollTop', $('#messages').attr('scrollHeight'));
			} else if (event.keyCode == 36) {
				$('#messages').attr('scrollTop', 0);
			}
		}
		if (event.keyCode == 38) {
			$('#messages').attr('scrollTop', $('#messages').attr('scrollTop') - 25);
		} else if (event.keyCode == 40) {
			$('#messages').attr('scrollTop', $('#messages').attr('scrollTop') + 25);
		} else if (event.keyCode == 33) {
			$('#messages').attr('scrollTop', $('#messages').attr('scrollTop') - 250);
		} else if (event.keyCode == 34) {
			$('#messages').attr('scrollTop', $('#messages').attr('scrollTop') + 250);
		}
	});
	$(window).resize(function() {
	  $('#messages').attr('scrollTop', $('#messages').attr('scrollHeight'));
	});
	var index = 0;
	var prefix;
	var completionList;
	$("#message").keydown(function (event) {
		if (event.keyCode == 9) {
			var m = /@(\w*)$/.exec($("#message").val());
			if (m) {
				if (prefix === undefined) {
					prefix = m[1].toLowerCase();
					completionList = [];
					index = 0;
					for (user in users) if (user.substring(0, prefix.length).toLowerCase() == prefix) completionList.push(user);
					completionList = completionList.sort();
				}
				if (index >= completionList.length) {
					index = 0;
				}
				if (completionList.length > index) {
					$("#message").val($("#message").val().substring(0, m.index+1) + completionList[index]);
					index += 1;
				}
			}
			event.preventDefault();
		}
		else {
			prefix = undefined;
		}
		if (event.keyCode == 27) {
			$('#message').val('');
		}
	});
	setTimeout(fetch);
	$("#message").focus();
	addAnnouncement("connected");
	function doWho() {
		$.ajax({
			url: '/who',
			dataType: 'json',
			cache: false,
			success: function(data) {
				if (data instanceof Array) {
					addAnnouncement("Currently chatting: " + data.join(", "));
					users = {};
					for (var i = 0; i < data.length; i++) {
						users[data[i]] = 1;
					}
				}
			},
			error: function() {
				addAnnouncement("error retrieving /who information");
			}
		});
	}
	setTimeout(doWho);
	$('#form').submit(function () {
		if ($("#message").val().substring(0, 4).toLowerCase() === '/who') {
			doWho();
		}
		else {
			$.post('/api', {'username': $("#username").val(), 'message': $("#message").val()}, null, 'json');
		}
		$("#message").val('');
		return false;
	});
	$("body").append($("<div>&nbsp;<span style='display:none'>&pi;</span></div>").css({
		position: 'absolute',
		bottom: '0px',
		right: '0px'
	}).hover(function () { $(this).children().fadeIn(200); }, function () { $(this).children().fadeOut(200); }));

	$(window).focus(function() {
		hasFocus = true;
		setTimeout(function() { document.title = 'chat.smarx'; }, 200);
		clearInterval(blinkyTitleInterval);
	});
	$(window).blur(function() {
		hasFocus = false;
		msgCount = 0;
	});
});