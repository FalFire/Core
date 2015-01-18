Dom = require 'dom'
Form = require 'form'
Icon = require 'icon'
Loglist = require 'loglist'
Obs = require 'obs'
Plugin = require 'plugin'
Db = require 'db'
Time = require 'time'
Ui = require 'ui'
Server = require 'server'

commonComment = (comment, unseen, likeId) !->
	Dom.section !->
		Dom.style
			Flex: 1
			marginLeft: '8px'
			margin: '4px'
		Dom.userText comment.c
		{t,u} = comment
		if u
			if likeId
				lastSeen = Db.personal.peek('likes', likeId)||0
				expanded = null
			Dom.div !->
				Dom.style
					textAlign: 'left'
					fontSize: '70%'
					color: '#aaa'
					padding: '2px 0 0'
				if u
					Dom.span !->
						Dom.style padding: '0 2px 0 0', color: (if unseen then '#5b0' else 'inherit')
						Dom.text Plugin.userName(u)
					Dom.text " • " if t?
				if t or t is 0
					Dom.span !->
						Dom.style padding: '0 2px'
						if t is 0
							Dom.text tr("sending")
							renderDots()
						else
							Time.deltaText t

				if likeId
					Dom.text " • "
					expanded = renderLike likeId, u, lastSeen

			Obs.observe !->
				if expanded?.get()
					renderLikeNames likeId, u, lastSeen


dots = ['.', '..', '...']
renderDots = !->
	i = Obs.create 0
	Obs.observe !->
		Dom.text dots[i.get()]
		Dom.span !->
			Dom.style
				color: 'transparent'
			Dom.text dots[2-i.get()]
	Obs.interval 500, !->
		i.modify (v) -> (v+1)%dots.length

exports.newComments = (id) ->
	cnt = Db.shared.get('comments', id, 'max')
	return 0 unless cnt
	seen = Db.personal.get('comments', id) || 0
	commentCnt = if seen<0 then -cnt-seen else cnt - seen # return negative number when not notifying

	# count likes as well
	likeCnt = 0
	for i in [1..cnt]
		likeCnt += newLikes(id+'-'+i)
	if likeCnt>0
		likeCnt + Math.abs(commentCnt)
	else
		commentCnt

exports.newLikes = newLikes = (id) ->
	return 0 if +Db.shared.get('likes', id, 'u') isnt Plugin.userId()
	lastSeen = Db.personal.peek('likes', id)||0

	cnt = 0
	cnt++ for uid, time of Db.shared.get('likes', id) when uid isnt 'u' and time>lastSeen
	cnt


exports.renderLikeNames = renderLikeNames = (id = 'default', aboutMemberId = 0, lastSeen = 0) !->
	toMe = aboutMemberId is Plugin.userId()
	Obs.observe !->
		if toMe
			newestLike = (time for uid, time of Db.shared.get('likes', id) when uid isnt 'u').sort().reverse()?[0]
			if newestLike and newestLike > lastSeen
				Server._sync "Social.seenLikes", Plugin.code(), id, newestLike, !->
					Db.personal.set 'likes', id, newestLike

	Dom.div !->
		Dom.style
			textAlign: 'left'
			fontSize: '70%'
			fontWeight: 'bold'
			color: '#aaa'
			padding: '2px 0 0'

		first = true
		likes = ({uid: uid, time: time} for uid, time of Db.shared.get('likes', id) when time>0 and uid isnt 'u')
		likes.sort((a, b) -> a.time - b.time)
		for {uid, time} in likes then do (uid, time) !->
			if first
				Icon.render data: 'thumbup', size: '13', color: '#aaa', style: {verticalAlign: 'bottom', margin: '0 2px 1px 1px'}
			else
				Dom.span ', '
			first = false
			Dom.span !->
				Dom.style whiteSpace: 'nowrap',padding: '5px 6px', margin: '-3px -3px'
				if toMe and time>lastSeen
					Dom.style color: '#5b0'
				Dom.text Plugin.userName(uid)
				Dom.onTap (!-> Plugin.userInfo(uid))

exports.renderLike = renderLike = (id = 'default', aboutMemberId = 0, lastSeen = 0) ->
	expanded = Obs.create false
	Dom.span !->
		liked = Db.shared.get('likes', id, Plugin.userId())
		Dom.style color: config('ui.accent'), padding: '5px 6px', margin: '-3px -3px'
		Dom.text if liked>0 then tr("Unlike") else tr("Like")
		Dom.onTap !->
			Server._sync 'Social.toggleLike', Plugin.code(), id, aboutMemberId, !->
				if liked
					Db.shared.set('likes', id, Plugin.userId(), -liked)

	# always expand when these are new likes the current user needs to see
	Obs.observe !->
		if +aboutMemberId is Plugin.userId()
			newestLike = (time for uid, time of Db.shared.get('likes', id) when uid isnt 'u').sort().reverse()?[0]
			expanded.set(true) if newestLike and newestLike > lastSeen

	Obs.observe !->
		cnt = 0
		cnt++ for k, v of Db.shared.get('likes', id) when k isnt 'u' and v>0
		if cnt>0 and !expanded.get()
			Dom.text " • "
			Dom.span !->
				Dom.style display: 'inline-block', padding: '5px 6px', margin: '-7px -3px'
				Icon.render data: 'thumbup', size: '13', color: config('ui.accent'), style: {verticalAlign: 'bottom', margin: '0 2px 1px 1px'}
				Dom.span !->
					Dom.style color: config('ui.accent')
					Dom.text cnt
				Dom.onTap !->
					expanded.set true
	expanded



exports.renderComments = (id = 'default',opts = {}) !->
	shared = Db.shared.ref('comments', id)
	personal = Db.personal.ref('comments', id)
	
	setSeen = (val) !->
		Server._sync "Social.seenComments", Plugin.code(), id, val, !->
			Db.personal.set 'comments', id, val

	lastSeen = 0|personal?.peek()
	Obs.observe !->
		if shared
			setSeen (if lastSeen<0 then -1 else 1) * max if (max=shared.get('max')) and !(Math.abs(lastSeen)>=max)

	Dom.div !->
		Dom.style margin: '8px'
		if shared
			Loglist.render 1, shared.func('max'), (cId) !->
				comment = shared.get(cId)
				return if typeof comment != 'object' or opts.render?(comment)
				if comment.u
					Dom.div !->
						Dom.style Box: "middle"
						Ui.avatar Plugin.userAvatar(comment.u), null, null, (!-> Plugin.userInfo(comment.u))
						commonComment comment, Math.abs(lastSeen)<cId, id+'-'+cId
				else
					commonComment comment

	return if opts.closed

	editingItem = Obs.create(false)
	Dom.div !->
		Dom.style Box: "middle", margin: '8px'

		Ui.avatar Plugin.userAvatar(), null, null, (!-> Plugin.userInfo(Plugin.userId()))

		addE = null
		save = !->
			return if !addE.value().trim()
			comment = Form.smileyToEmoji addE.value()
			Server._sync "Social.comment", Plugin.code(), id, comment, !->
				if shared
					newMax = shared.incr 'max'
					shared.set newMax,
						c: comment
						t: 0
						u: Plugin.userId()

			addE.value ""
			editingItem.set(false)
			Form.blur()

		Dom.section !->
			Dom.style Box: "middle", Flex: 1, margin: '4px'
			Dom.div !->
				Dom.style Flex: 1
				addE = Form.text
					autogrow: true
					name: 'comment'
					text: tr("Add a comment")
					simple: true
					onChange: (v) !->
						editingItem.set(!!v?.trim())
					onReturn: save
					inScope: !->
						Dom.prop 'rows', 1
						Dom.style
							border: 'none'
							width: '100%'
							fontSize: '100%'

			Ui.button !->
				Dom.style
					marginRight: 0
					visibility: (if editingItem.get() then 'visible' else 'hidden')
				Dom.text tr("Add")
			, save


	Dom.div !->
		Dom.style marginTop: '14px'
		Form.sep()
		Form.check
			name: 'notify'
			value: !((0|(personal?.get())) < 0)
			text: tr("Notify me of new comments")
			onSave: (v) !->
				if shared
					setSeen (if v then 1 else -1) * shared.peek("max")

