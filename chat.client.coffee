Db = require 'db'
Dom = require 'dom'
Form = require 'form'
Obs = require 'obs'
Page = require 'page'
Photo = require 'photo'
Plugin = require 'plugin'
Server = require 'server'
Time = require 'time'
Ui = require 'ui'
{tr} = require 'i18n'

exports.renderMessages = (opts) !->

	firstRender = true

	dataO = opts.dataO || Db.shared
	firstO = opts.firstO || Page.state.ref('first')
	newCount = opts.newCount || 0

	maxIdO = dataO.ref('maxId')
	if !firstO.peek()
		heightCount = Math.round(Dom.viewport.peek('height')/50) + 5
		msgCount = Math.max(10, (if newCount > 100 then 0 else newCount), heightCount)
			# if more than 100 unseen, don't even try
		log 'unread=', newCount, 'height=', heightCount, 'msgCount=', msgCount
		firstO.set Math.max(1, (maxIdO.peek()||0)-msgCount)

	screenE = Dom.get()
	Dom.div !->
		if firstO.get()==1
			# todo: render opts.before?
			Dom.style display: 'none'
			return
		Css 'chat-earlier',
			padding: '4px'
			textAlign: 'center'

		Ui.button tr("Earlier messages"), !->
			nfv = firstO.modify (v) -> Math.max(1, (v||0)-10)
			prevHeight = screenE.prop('scrollHeight')
			Obs.onStable !->
				delta = screenE.prop('scrollHeight') - prevHeight
				# does not account for case when contentHeight < scrollHeight, but that should happen
				Page.scroll Page.scroll() + delta

	wasNearBottom = true
		# Observers are always called in order: update wasNearBottom flag before
		# new messages are inserted. After insertion, a similar observer uses the
		# flag to scroll down
	Obs.observe !->
		maxIdO.get()
		wasNearBottom = Page.nearBottom()

	log 'firstO=', firstO.peek(), 'maxO=', maxIdO.peek()

	require('loglist').render firstO, maxIdO, (num) !->
		#log 'render', num
		if firstRender and num is maxIdO.peek() - newCount + 1
			Dom.div !->
				Css 'chat-new',
					margin: '8px -8px'
					textAlign: 'center'
					padding: '4px'
					background: '#f5f5f5'
					color: '#5b0'
					textShadow: '0 1px 0 #fff'
					fontWeight: 'bold'
					borderBottom: '1px solid #fcfcfc'
					borderTop: '1px solid #d0d0d0'
					fontSize: '80%'
				Dom.text tr("▼ New messages")

		opts.content dataO.ref(0|num/100, num%100), num

	Obs.observe !->
		maxIdO.get()
		if firstRender
			if newCount < 10
				Page.scroll 'down' # no scroll-animation on first render
		else if wasNearBottom
			Page.scroll 'down', true
		else
			require('toast').show tr("Scroll for new message")

	firstRender = false


exports.renderInput = (opts={}) !->
	dataO = opts.dataO || Db.shared
	draftO = opts.draftO || Db.local.ref('draft')
	# opts.typing
	# opts.photo

	Css 'chat-input',
		background: '#f5f5f5'
		borderTop: 'solid 1px #aaa'
		'# > div':
			background: '#fff'
			border: 'solid 1px #aaa'
			borderRadius: '6px'
			margin: '6px 60px 6px 6px'
			padding: '4px 2px'
		'# textarea':
			width: '100%'
			fontSize: '17px'
			border: 'none'
			borderColor: 'transparent'
			background: 'transparent'
			padding: '0'
			margin: '0'
			fontFamily: 'Helvetica,sans-serif' # for android 4.4

	inputE = false
	isTyping = false
	initValue = draftO.peek() || ''
	emptyO = Obs.create(initValue=='')

	send = !->
		msg = inputE.value()
		log 'send', msg
		if msg
			msg = Form.smileyToEmoji msg
			Server.sync 'chat', msg, opts.rpcArg||null, !->
				id = dataO.modify 'maxId', (v) -> (v||0)+1
				dataO.set Math.floor(id/100), id%100,
					by: Plugin.userId()
					text: msg
			if opts.typing
				Server.send 'typing', isTyping=false
			emptyO.set true
			inputE.value ''

	Dom.div !->
		# wrap TextArea in a DIV, otherwise chaos ensues
		inputE = Form.text
			simple: true
			autogrow: true
			value: initValue
			onReturn: (value,evt) !->
				if !Plugin.agent().ios && !evt.prop('shiftKey')
					evt.kill true, true
					send()
			inScope: !->
				Dom.prop 'rows', 1
				Dom.on 'input', !->
					value = inputE.value()
					emptyO.set(value=='')
					if opts.typing and (value isnt '') != isTyping
						Server.send 'typing', isTyping=(value isnt '')

				Obs.onClean !->
					value = inputE.value()
					draftO.set value||null
					if opts.typing and value
						Server.send 'typing', isTyping=false

	Obs.observe !->
		choosePhoto = opts.photo isnt false && emptyO.get()
		# todo: predict un-uploaded photo using Photo.unclaimed?
		require('icon').render
			style:
				position: 'absolute'
				padding: '10px'
				bottom: 0
				right: 0
			color: if choosePhoto then '#555' else Plugin.colors().highlight
			size: 36
			data: if choosePhoto then 'camera' else 'send'
			onTap:
				noBlur: true
				cb: !->
					if choosePhoto
						Photo.pick undefined, opts.rpcArg||true
					else
						send()

Css false,
	'.chat-msg':
		position: 'relative'
		margin: '4px -4px'
	'.chat-msg.chat-me':
		textAlign: 'right'
	'.chat-msg .ui-avatar':
		position: 'absolute'
		top: '4px'
		margin: 0
		left: 0
	'.chat-msg.chat-me .ui-avatar':
		left: 'auto'
		right: 0
	'.chat-content':
		display: 'inline-block'
		margin: '2px 50px'
		padding: '6px 8px 4px 8px'
		minHeight: '32px'
		borderRadius: '4px'
		_boxShadow: '0 2px 0 rgba(0,0,0,.1)'
		textAlign: 'left'
		background: '#fff'
		_userSelect: 'text'
	'.chat-content img':
		width: '120px'
		height: '120px'
		_objectFit: 'cover'
	'.chat-info':
		textAlign: 'left'
		fontSize: '70%'
		color: '#aaa'
		padding: '2px 0 0'
