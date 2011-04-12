var should_underline = false;
function toggle() {
	$('a.blinky').css('text-decoration',
		should_underline
		? 'underline'
		: 'none'
	);
	should_underline = !should_underline;
	setTimeout(toggle, 1000);
}

$(function() {
	setTimeout(toggle, 1000);
});