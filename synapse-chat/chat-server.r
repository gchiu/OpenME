Rebol [
    title: "EMR Chat Server"
    author: "Graham Chiu"
    rights: "GPL Copyright 2005"
    date: 3-Mar-2006
    version: 0.0.14
    encap: [ title "Synapse Chat Server v 0.0.16 " quiet secure none]
    changes: {
        30-Dec-2005 added chat server functions.
        3-Oct-2005 specialty
        2-Oct-2005 gps
        25-Sep-2005 appts
        23-Sep-2005 delete problem, tickler
        22-Sep-2005 add-problem, add-tickler, add-diagnosis
        21-Sep-2005 add-consult
    }
]

server-version: 0.0.16
expiry_date: 1-Jan-2015 ;28-Apr-2007

args: system/options/args


calcMD5: func [ binData ] [
    return enbase/base checksum/method binData 'md5 16
]

#include  %/c/rebol-sdk-276/source/prot.r
#include  %/c/rebol-sdk-276/source/view.r

errlo: layout [vh3 "An error has occurred." 400
    errtitle: text 400 wrap
    errmsg: area 400x200 wrap
    btn blue "Okay" [hide-popup]
]

odbc.jpg: load #include-binary %odbc.jpg
running.jpg: load #include-binary %running.jpg
select.jpg: load #include-binary %select.jpg
driver.jpg: load #include-binary %driver.jpg
admin.jpg: load #include-binary %admin.jpg
display: func[v][
 print ["display:" mold v]
]

#include %/c/rebol/rebgui/beer2/libs/aa.r
#include %/c/rebol/rebgui/beer2/libs/catch.r
#include %/c/rebol/rebgui/beer2/libs/iatcp-protocol.r


#include %/c/rebol/rebgui/beer2/beer/channel.r
#include %/c/rebol/rebgui/beer2/beer/frameparser.r
#include %/c/rebol/rebgui/beer2/beer/frameread.r
#include %/c/rebol/rebgui/beer2/beer/framesend.r
#include %/c/rebol/rebgui/beer2/beer/session-handler.r
#include %/c/rebol/rebgui/beer2/beer/authenticate.r
#include %/c/rebol/rebgui/beer2/beer/profiles.r
; #include %profiles.r
encoding-salt: #{D75B94668DC29BE2B2695781AE1732F7EC89C61D}
;; #include %/c/rebol/rebgui/beer/examples/encoding-salt.r
#include %/c/rebol/rebgui/beer/examples/echo-profile.r
#include %/c/rebol/rebgui/beer2/beer/initiator.r
#include %/c/rebol/rebgui/beer2/beer/listener.r
#include %/c/rebol/rebgui/beer2/beer/profiles/rpc-profile.r

;; ft-profile is custom profile to upload from %chat-uploads/
#include %/c/rebol/rebgui/beer2/beer/profiles/ft-server-profile.r
; #include  %/d/rebole/BEER-SDK/beer/profiles/pubtalk-profile-new.r
prefs-obj: make object! [
    username: language: tz: status: email: city: longitude: latitude: none
]

Eliza-obj: make prefs-obj [
    username: "Eliza" language: "EN" status: "present" email: "compkarori@gmail.com" tz: now/zone city: "Wellington"
]


chatroom-peers: make block! [] ;maintains the list of active peers in a conversation
eliza-on: false
; user-table: copy ["0.0.0.0:0" "Eliza" "present"] ; [ ipaddress:port username state ]
; user-table: copy/deep [ "0.0.0.0:0" Eliza-obj ] 

user-table: copy []
repend user-table ["0.0.0.0:0" Eliza-obj]
chat-links: copy []
if exists? %chat-links.r [
    attempt [
        chat-links: load %chat-links.r
    ]
]

comment {
}

;;; rebuild user table

rebuild-user-table: func [/local temp-table state t] [
    ; now rebuild the user-table, and the chat-users list
    temp-table: copy user-table
    ; user-table: copy [ "0.0.0.0:0" "Eliza" "present" ]

    user-table: copy []
    repend user-table ["0.0.0.0:0" Eliza-obj]
    ;; now should get all the registered users and add them
    insert db-port {select userid, city, email, tz, laston, longitude, latitude from users where activ = 'T'}
    cnt: 1
    foreach record copy db-port [
        probe record/5
        state: copy "-"

        if found? record/5 [
            state: now/zone + difference now record/5
            ?? state
            either state > 24:00 [
                state: rejoin [record/5/day "-" record/5/month]
            ] [
                t: form state
                state: copy/part t find/last t ":"
            ]
        ]
        ; ?? state
        if none? record/6 [record/6: copy ""]
        if none? record/7 [record/7: copy ""]
        repend user-table [join "0.0.0.0:" cnt
            make prefs-obj [
                username: record/1
                tz: record/4
                city: record/2
                email: record/3
                longitude: record/6
                latitude: record/7
                status: state
            ]
        ]
        cnt: cnt + 1
    ]
    ; probe user-table


    ; chat-users: copy reduce ["Eliza" "present" "0.0.0.0" "0"]
    ; should now rebuild the user-table of ip-port, username, state
    foreach channel chatroom-peers [
        attempt [
            ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
            either found? ndx: find temp-table ip-port [
                ; user was here before
                ; repend user-table [ ndx/1 ndx/2 ]
                ; need to change the existing table.
                ; get the userid out

                forskip user-table 2 [
                    ; if we find the user in the chatroom-peers, we take their ip-port and status, and overwrite the one in the user-table
                    ; print ["Looking at " user-table/2/username]
                    if user-table/2/username = channel/port/user-data/username [
                        user-table/1: ip-port
                        user-table/2: ndx/2
                        break
                    ]
                ]
                user-table: head user-table
                ; repend chat-users [ ndx/2 ndx/3 channel/port/sub-port/remote-ip channel/port/sub-port/remote-port ]
            ] [
                ; not in the old user-table, so must be new arrivee
                ; or duplicate?  To prevent two users, let's overwrite the existing one
                forskip user-table 2 [
                    ; print ["Looking at " user-table/2/username]
                    if user-table/2/username = channel/port/user-data/username [
                        user-table/1: ip-port
                        ; user-table/2: ndx/2
                        user-table/2/status: "arrived"
                        break
                    ]
                ]
                user-table: head user-table
            ]
        ]
    ]
    print ["after removal users: " length? chatroom-peers]
    print "user table"
    probe user-table
    ; print "chat-users"
    ; probe chat-users
    ; msg-to-all mold/all reduce ['cmd reduce ['set-userstate chat-users]]
    update-room-status
]

;;; end of rebuild user table




register context [
    profile: 'PUBTALK-ETIQUETTE ; profile name
    version: 1.0.0 ; version of the profile
    init: func [
        {Initialize channel specific data and dynamic handlers - called by any new connection}
        channel [object!] ; the channel to be initialized
    ] [; new channel created register the peer into the chatroom-peers 
        ; this is only required in the server, so that it can replicate 
        ; the posted messages.
        if channel/port/user-data/role = 'L [
            append chatroom-peers :channel
            print [" New user has arrived. Number of channels in room = " length? chatroom-peers]

            ; let's see what's in the port
            ; write %port.r mold channel/port
            rebuild-user-table
        ]

        ; create the private profile data
        channel/prof-data: make object! [
            ; we don't require any private data for this profile
        ]

        ; set the read-msg handler
        channel/read-msg: func [
            {handle incoming MSGs}
            channel
            msg
        ] [
            ; display msg/payload
            ; probe msg/payload
            ack-msg channel
            clientmsg: load msg/payload

            print "raw message"
            probe clientmsg


            comment {
[ chat [ ] [ user color msg color color date font ]]

; chat message to some 
[ chat [ u1 u2 .. ] [ user color msg color color date font ] ]

; cmd message to server

[ cmd [ set-users ]] ; get the users
[ cmd [ set-state "away" ]] ; set user state

; cmd message to client

[ cmd [ set-users ]] ; set the users and status

[ action [ user ] [ the action ]]

[ action [ "guest" ] [ 'nudge ]]

}

            case [
                parse clientmsg ['pchat set userblock block! set clientmsg block! to end] [
                    print "private message - check for Eliza"
                    probe userblock

                    ;					msg-to-all msg/payload
                    ; return the message to the sender but with a timestamp
                    insert tail clientmsg now ;; first time insert

                    ;; generate the id					
                    use [private-msg err2 txt maxmsgid] [
                        if error? set/any 'err2 try [
                            private-msg: load msg/payload

                            insert tail private-msg/3 now
                            ?? private-msg
                            ; need to remove the text and save that separately so that can be searched on
                            txt: copy private-msg/3/3
                            ; and now we remove the txt from the message
                            private-msg/3/3: copy ""
                            insert db-port [{insert into CHAT ( author, CHANNEL, msg, format, ctype ) values (?, ?, ?, ?, ?) } private-msg/3/1 private-msg/2/1 txt private-msg "P"]
                            print "Private message saved into chat table"
                        ] [
                            print "Insert chat message failed because..."
                            probe mold disarm err2
                            msg-to-all mold/all reduce ['gchat
                                ["lobby"]
                                reduce ["Hal4000" red rejoin ["Server error on insert: " mold disarm err2] black white [bold] now]
                            ]
                        ]
                    ]
                    insert db-port {select max(msgid) from chat}
                    maxmsgid: pick db-port 1
                    insert tail clientmsg maxmsgid/1
                    post-msg1 channel mold/all reduce [
                        'pchat
                        reduce [userblock/1]
                        clientmsg
                    ]
                    ; check to see if message is for Eliza ie. userblock/1 = "0.0.0:0"
                    comment {
chat-links: [[gchat ["lobby"] ["Graham" 128.128.128 "this is a link http://www.rebol.com" 0.0.0 240.240.240
 []]] [gchat ["lobby"] ["Graham" 128.128.128 "http://www.compkarori.com/reb/pluginchat40.r" 0.0.0 240.240.2
40 []]]]
}

                    either any [userblock/1 = "Eliza" userblock/1 = "0.0.0.0:0" userblock/1 = "0:0" userblock/1 = "0.0.0:0"] [
                        print "message for Eliza"
                        case [
                            find/part clientmsg/3 "search " 7 [
                                use [terms msg ok] [

                                    if not empty? msg: trim find/tail clientmsg/3 #" " [
                                        terms: parse/all msg " "
                                        foreach msgblock chat-links [
                                            msg: msgblock/3/3
                                            ok: true
                                            foreach term terms [
                                                if not find msg term [
                                                    ok: false
                                                    break
                                                ]
                                            ]
                                            if ok [
                                                msgblock/1: 'pchat
                                                msgblock/2/1: "Eliza"
                                                post-msg1 channel mold/all msgblock

                                            ]
                                        ]
                                    ]

                                ]
                            ]
                            any [
                                find/part clientmsg/3 "help" 4
                                find/part clientmsg/3 "aide" 4


                            ] [
                                print "found help message"
                                use [ip-port ndx] [
                                    ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                    if found? ndx: find user-table ip-port [
                                        lang: ndx/2/language
                                    ]
                                    ; now update everyone
                                    update-room-status
                                ]
                                if none? lang [
                                    case [
                                        find/part clientmsg/3 "aide" 4 [lang: "FR"]
                                    ]
                                ]


                                help-msg:
                                switch/default lang [
                                    "FR" [
                                        {Les commandes suivantes sont disponibles dans tous les channels (salons)
'/cmd 'status word! ex: /cmd status sleeping (Change le statut de connexion)
'/cmd 'new date! ex: /cmd new 18-Jan-2006/9:00 (nouveaux messages à partir de date! GMT+13:00 sauf indication contraire)
'/cmd 'new date! ex: /cmd new 18-Jan-2006/9:00+0:00 (GMT)
'/cmd 'new time! (heure = 0:00 + 13:00)
'/cmd 'new date! 'by "userid" 'in "room"
'/cmd 'city Paris
'/cmd 'email email@address.com
'cmd 'language FR (Langue) 
'cmd 'show 'groups (Affiche tous les groupes et le nombre de messages)

 Les commandes suivantes sont disponibles dans mon salon :
 'help ex: help (donne ce message d'aide)
 'search word1 ... wordn ex: search whywire (recherches du texte dans toutes les URL archivées.)

Le bouton "Stylo" est utilisé pour faire apparaître l'éditeur de texte. Il éditera un fichier ou une URL valide trouvé dans la zone de saisie du chat. S'il n'y a aucun fichier ou URL valide, il essayera d'exécuter le contenu comme du code Rebol. 

Les messages sont sauvés automatiquement s'ils contiennent http, ftp:// et le mailto : 

 Le passage de la souris sur les boutons fait apparaître un texte d'aide dans la partie inférieure gauche de la fenêtre.

Un click de souris sur le texte rouge de la barre de boutons fait glisser la barre de bouton à gauche. }
                                    ]

                                ] [
                                    {The following commands are available in any channel
'/cmd 'status word! eg: /cmd status sleeping ( changes online status )
'/cmd 'new date! eg: /cmd new 18-Jan-2006/9:00 ( new messages from date! assuming timezone GMT+13:00 unless otherwise specified )
'/cmd 'new date! eg /cmd new 18-Jan-2006/9:00+0:00 ( from GMT )
'/cmd 'new date! 'by "userid" 'in "room"
'/cmd 'new today ( from time 0:00+13:00 )
'/cmd 'timezone time! ( set time zone )
'/cmd 'city CityName
'/cmd 'email email@address.now
'/cmd 'language EN ( set language to english )
'/cmd 'show 'groups ( show all groups that have existed)

The following commands are available in my channel
'help eg. help ( gives this help message )
'search word1 ... wordn eg. search whywire ( searches for the text in any saved url )

The Pen button is used to bring up an editor.  It will edit a valid file or url found in the chatbox area.
If there is no valid file or url there, it will attempt to execute the contents as Rebol code.

Messages are saved automatically if they contain http, ftp:// and mailto:

The buttons contain mouseover help which appears bottom left.

Clicking on the red text on the button bar slides the button bar left.
}

                                ]




                                post-msg1 channel mold/all reduce [
                                    'pchat
                                    ["Eliza"]
                                    reduce ["Eliza" red help-msg black white [] now]
                                ]
                            ]

                            true [; not a command to Eliza, so must be chatting to her
                                if error? try [
                                    eliza-says: copy match clientmsg/3
                                ] [
                                    eliza-says: "Oops, I just had a little petit mal aka parse error."
                                ]
                                post-msg1 channel mold/all reduce ['pchat
                                    ["Eliza"]
                                    reduce
                                    ["Eliza" red rejoin [clientmsg/1 ", " eliza-says] black white [] now]
                                ]
                            ]
                        ]
                        return
                    ] [
                        ; not for Eliza, lets save it
                        ;;; remove this for no database storage
                        ;; save private messages
                        comment { we will have to save all messages :(

                        use [private-msg err2 txt maxmsgid] [
                            if error? set/any 'err2 try [
                                private-msg: load msg/payload

                                insert tail private-msg/3 now
                                ?? private-msg
                                ; need to remove the text and save that separately so that can be searched on
                                txt: copy private-msg/3/3
                                ; and now we remove the txt from the message
                                private-msg/3/3: copy ""
                                insert db-port [{insert into CHAT ( author, CHANNEL, msg, format, ctype ) values (?, ?, ?, ?, ?) } private-msg/3/1 private-msg/2/1 txt private-msg "P"]
                                print "Private message saved into chat table"
                                insert db-port {select max(msgid) from chat}
                                maxmsgid: pick db-port 1
                                insert tail private-msg/3 maxmsgid/1

                            ] [
                                print "Insert chat message failed because..."
                                probe mold disarm err2
                                msg-to-all mold/all reduce ['gchat
                                    ["lobby"]
                                    reduce ["Hal4000" red rejoin ["Server error on insert: " mold disarm err2] black white [bold] now]
                                ]
                            ]
                        ]
}


                    ]

                    ; now to send it on to the right person !

                    ; don't do anything else if the sender is also the origin
                    ;; need to change this to send to name of recipient instead of ip address.

                    use [from-ip-port ip-port] [
                        ; don't send to sender if also origin
                        if error? set/any 'err try [; in case username disappears?
                            if userblock/1 = channel/port/user-data/username [return]
                        ] [
                            print "Error checking if recipient is sender"
                            probe disarm err
                        ]
                        ; from-ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                        ; if from-ip-port = userblock/1 [return] ; don't send to sender if also origin
                        ; ip-port: parse/all userblock/1 ":"

                        print ["sending private message to " userblock/1]
                        foreach chan chatroom-peers [
                            if error? set/any 'err try [; in case username disappears
                                probe chan/port/user-data/username
                                if chan/port/user-data/username = userblock/1 [
                                    print "found addressee"
                                    post-msg1 chan mold/all reduce [
                                        'pchat
                                        reduce [channel/port/user-data/username]
                                        clientmsg
                                    ]

                                    break

                                ]
                            ] [
                                print "Error sending private message to user"
                                probe disarm err
                            ]
                        ]
                    ]

                ]

                parse clientmsg ['cmd set usercmd block!] [
                    print "cmd coming"
                    ?? clientmsg
                    author: group: none
                    case [
                        ; clientmsg: [cmd [edit 3670 "I've changed this text!!"]]

                        parse usercmd ['edit set msgno integer! set msg string! to end] [
                            use [reply err  addressee] [
                                if error? set/any 'err try [
                                    msg: rejoin [msg {^/^/Updated on } now " by " channel/port/user-data/username]
                                    insert db-port [{select * from chat where msgid = (?) and author = (?)} msgno channel/port/user-data/username]
                                    either none? pick db-port 1 [
                                        reply: join "You did not have the right to edit this message " msgno
                                        post-msg1 channel mold/all reduce [
                                            'gchat
                                            ["lobby"]
                                                reduce ["Hal4000" red
                                                reply
                                                black white [] now
                                            ]
                                        ]
                                        return
                                    ][
                                        insert db-port [{ update chat set msg = (?) where msgid = (?) and author = (?)} msg msgno channel/port/user-data/username]

                                          print "insert finished"
                                       reply: rejoin ["Message " msgno " was updated."]
                                    ]

                                    ;; only update public messages!!
                                    insert db-port [{select author, channel, ctype from chat where msgid = (?)} msgno ]
                                    result: pick db-port 1
                                    either result/3 = "G"
                                    [

                                        msg-to-all mold/all reduce [
                                            'cmd
                                            reduce ['revise msgno msg]
                                        ]
                                    ][
                                        ;; private message
                                        post-msg1 channel mold/all reduce [
                                            'cmd
                                            reduce ['revise msgno msg ]
                                        ]
                                        ;; now update the message for the addressee
                                        addressee: result/2
                                        ?? addressee
                                        send-to-user addressee mold/all reduce [ 'cmd reduce [ 'revise msgno msg ] ]                                    
                                    ]
                                ] [
                                    probe disarm err
                                    reply: "A sql error occurred on attempted message update."
                                ]
                                post-msg1 channel mold/all reduce [
                                    'gchat
                                    ["lobby"]
                                    reduce ["Hal4000" red
                                        reply
                                        black white [] now
                                    ]
                                ]
                            ]
                        ]
                        ; [cmd update-self compkarori@gmail.com "Wellington" -41.285 174.737]

                        parse usercmd ['update-self set email email! set city string! set latitude [decimal! | integer!] set longitude [decimal! | integer!] to end] [
                            print "found update-self command ... "
                            if error? set/any 'err try [
                                insert db-port [{update users set email = (?), city = (?), longitude = (?), latitude = (?) where userid = (?)} email city longitude latitude channel/port/user-data/username]
                                msg: join channel/port/user-data/username "'s details updated okay"
                                ?? msg
                                ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                if found? ndx: find user-table ip-port [
                                    ; ndx/3: copy userstate
                                    ndx/2/email: email
                                    ndx/2/longitude: longitude
                                    ndx/2/latitude: latitude
                                    ndx/2/city: copy city
                                ]
                                ; now update everyone
                                update-room-status

                            ] [
                                err: mold disarm err
                                msg: join "Database error occurred on update^/" err
                            ]
                            post-msg1 channel mold/all reduce [
                                'gchat
                                ["lobby"]
                                reduce ["Hal4000" red
                                    msg
                                    black white [] now
                                ]
                            ]
                        ]

                        parse usercmd ['get 'groups to end] [
                            print "get groups command received"
                            use [group-list] [
                                group-list: copy []
                                insert db-port [{select distinct channel from chat where ctype = (?)} "G"]
                                foreach record copy db-port [
                                    ;; send all the messages to the requester
                                    if found? record/1 [
                                        append group-list record/1
                                    ]
                                ]
                                ?? group-list
                                post-msg1 channel mold/all reduce [
                                    'cmd
                                    reduce ['groups group-list]
                                ]
                            ]
                        ]
                        parse usercmd ['show 'groups to end] [
                            use [group-list out] [
                                group-list: copy []
                                insert db-port [{select distinct channel from chat where ctype = (?)} "G"]
                                foreach record copy db-port [
                                    ;; send all the messages to the requester
                                    if found? record/1 [
                                        append group-list record/1
                                    ]
                                ]
                                ;; got all the groups, now get all the messages in each group
                                foreach group copy group-list [
                                    insert db-port [{select count(msg) from chat where channel = (?)} group]
                                    cnt: pick db-port 1
                                    insert find/tail group-list group cnt
                                ]
                                out: copy "Unique Groups and Message counts^/"
                                foreach [group cnt] group-list [
                                    repend out [group " " cnt newline]
                                ]
                                post-msg1 channel mold/all reduce [
                                    'gchat
                                    ["lobby"]
                                    reduce ["Hal4000" red
                                        out
                                        black white [] now
                                    ]
                                ]

                                ; post-msg1 channel out

                            ]
                        ]

                        ; [cmd [timezone 13:00]]
                        parse usercmd ['timezone set timezone [string! | time!]] [
                            print "Timezone command received"
                            use [status ip-port ndx] [
                                ; ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                                ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                if found? ndx: find user-table ip-port [
                                    ; ndx/3: copy userstate
                                    ndx/2/tz: form timezone
                                ]
                                ; update database
                                insert db-port [{update users set tz = (?) where userid = (?)} form timezone channel/port/user-data/username]
                                ; now update everyone
                                update-room-status
                            ]
                        ]

                        parse usercmd ['city set city string!] [
                            use [status ip-port ndx] [
                                ; ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                                ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                if found? ndx: find user-table ip-port [
                                    ; ndx/3: copy userstate
                                    ndx/2/city: copy city
                                ]
                                ; update database
                                insert db-port [{update users set city = (?) where userid = (?)} city channel/port/user-data/username]
                                ; now update everyone
                                update-room-status
                            ]
                        ]
                        parse usercmd ['language set language string!] [
                            use [status ip-port ndx] [
                                ; ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                                ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                if found? ndx: find user-table ip-port [
                                    ; ndx/3: copy userstate
                                    ndx/2/language: copy language
                                ]
                                ; now update everyone
                                update-room-status
                            ]
                        ]
                        parse usercmd ['email set email string!] [
                            use [status ip-port ndx] [
                                ; ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                                ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                if found? ndx: find user-table ip-port [
                                    ; ndx/3: copy userstate
                                    ndx/2/email: copy email

                                    insert db-port [{update users set email = (?) where userid = (?)} channel/port/user-data/username email]
                                ]
                                ; now update everyone
                                update-room-status
                            ]
                        ]
                        parse usercmd ['sync set msgs-from date!] [
                            ?? msgs-from
                            insert db-port [{select count(msg) from chat where msgdate >  (?)} msgs-from]
                            cnt: pick db-port 1
                            if found? cnt [cnt: cnt/1]
                            if any [none? cnt cnt = 0] [
                                reply-query channel "Eliza" rejoin ["There are no messages waiting for syncing from " msgs-from]
                            ]
                            if (cnt >= 30) [
                                print ["cnt is > 30 " cnt]
                                reply-query channel "Eliza" rejoin ["There are " cnt " messages waiting for syncing from " msgs-from ". Use the Quote button (next to Pen button) to paste into console"]
                            ]
                            if all [cnt > 0 cnt < 30] [

                                use [err3 err4] [
                                    post-msg1 channel mold/all reduce [
                                        'cmd
                                        reduce ['downloading 'started]
                                    ]
                                    if error? set/any 'err3 try [
                                        insert db-port [{select msg, format, ctype, msgid from chat where msgdate > (?) order by msgdate asc} msgs-from]

                                        print "new db extract - 1"
                                        foreach record copy db-port [
                                            ;; send all the messages to the requester
                                            if found? record/1 [
                                                ?? record
comment {
record: [{this should revise shouldn't it.

Updated on 10-Mar-2006/9:04:58+13:00 by Graham} {[pchat ["Graham"] ["Graham" 128.128.128 "" 0.0.0 240.240.240 [] 10-Mar-2006/9:04:51+13:00]]} "P" 6]

}                                                
                                                print "record found..."
                                                rec: to-block record/2
                                                ?? rec
                                                rec/1/3/3: record/1
                                                insert tail rec/1/3 record/4
                                                either record/3 = "G" [
                                                    post-msg1 channel mold/all rec/1
                                                ] [
                                                    ; a private message - only send it if recipient is the requester
                                                    ; or origin is the requester
                                                    ; if the recipient of the private message is the requester, then change
                                                    ; so that the recipient is the sender
                                                    if any [channel/port/user-data/username = rec/1/2/1
                                                        channel/port/user-data/username = rec/1/3/1] [
                                                        if channel/port/user-data/username = rec/1/2/1 [
                                                            rec/1/2/1: copy rec/1/3/1
                                                        ]
                                                        post-msg1 channel mold/all rec/1
                                                    ]
                                                ]
                                            ]
                                        ]
                                    ] [
                                        print "Database retrieve error"
                                        probe mold disarm err3
                                    ]
                                    post-msg1 channel mold/all reduce [
                                        'cmd
                                        reduce ['downloading 'finished]
                                    ]
                                ] ;; end of message downlaod
                            ]
                        ]

                        parse usercmd
                        ['new set msgs-from date! (group: none) opt ['by set author [string! | word!]] opt ['in set group [string! | word!]] end] [

                            ; parse usercmd ['new set msgs-from date!] [
                            ;; retrieve all old messages
                            print "New message received"
                            ?? msgs-from
                            use [err2 result] [
                                result: copy []
                                post-msg1 channel mold/all reduce [
                                    'cmd
                                    reduce ['downloading 'started]
                                ]
                                if error? set/any 'err2 try [
                                    case [
                                        all [none? author none? group] [
                                            insert db-port [{select msg, format, ctype, msgid from chat where msgdate > (?) order by msgdate asc} msgs-from]
                                        ]
                                        all [none? author not none? group] [
                                            ; lowercase group
                                            insert db-port [{select msg, format, ctype, msgid from chat where msgdate > (?) and channel = (?) order by msgdate asc} msgs-from group]
                                        ]
                                        all [not none? author none? group] [
                                            ; lowercase author
                                            insert db-port [{select msg, format, ctype, msgid from chat where msgdate > (?) and author = (?) order by msgdate asc} msgs-from author]
                                        ]
                                        all [not none? author not none? group] [
                                            ; lowercase author lowercase group
                                            insert db-port [{select msg from, format, ctype, msgid from chat where msgdate > (?) and author =(?) and CHANNEL = (?) order by msgdate asc} msgs-from author group]
                                        ]
                                    ]

                                    ;									insert db-port [{select msg, format from chat where msgdate > (?) order by msgdate asc} msgs-from]

                                    print "new db extract - 3"
                                    foreach record copy db-port [
                                        ;; send all the messages to the requester
                                        ?? record
                                        if found? record/1 [
                                            comment {
    record: ["testing." {[gchat ["Test"] ["Graham" 0.145.0 "" 0.0.0 240.240.240 [] 7-Mar-2006/18:30:49+13:00]]} "G" 3729]
rec: [[gchat ["Test"] ["Graham" 0.145.0 "testing." 0.0.0 240.240.240 [] 7-Mar-2006/18:30:49+13:00]]]
}

                                            rec: to-block record/2
                                  ?? rec          
                                            rec/1/3/3: record/1
                                            insert tail rec/1/3 record/4
                                            ; rec: [[gchat ["lobby"] ["Graham" 0.0.156 "lobby message" 0.0.0 240.240.240 [] 11-Feb-2006/16:11:44+13:00]]]
                                            either record/3 = "G" [
                                                post-msg1 channel mold/all rec/1
                                            ] [ 
                                                ; a private message - only send it if recipient is the requester
                                                ; or origin is the requester
                                                ; if the recipient of the private message is the requester, then change
                                                ; so that the recipient is the sender
                                                if any [channel/port/user-data/username = rec/1/2/1
                                                    channel/port/user-data/username = rec/1/3/1] [
                                                    if channel/port/user-data/username = rec/1/2/1 [
                                                        rec/1/2/1: copy rec/1/3/1
                                                    ]
                                                    append/only result rec/1
                                                    ; post-msg1 channel mold/all rec/1
                                                ]
                                            ]
                                        ]
                                    ]
                                    ; now deal with the private messages
                                                                                ;; if any private messages, then it was a check of a private group, or off all.
                                            if any [ not none? group not empty? result] [ ; a potentially private group was selected
                                                ; if this was a search on a private channe, so we now need to get the messages we sent to this group
                                                insert db-port [{select msg, format, ctype, msgid from chat where msgdate > (?) and channel = (?) order by msgdate asc} msgs-from channel/port/user-data/username]
                                                foreach record copy db-port [
                                                    rec: to block record/2

                                            comment {
    record: ["testing." {[gchat ["Test"] ["Graham" 0.145.0 "" 0.0.0 240.240.240 [] 7-Mar-2006/18:30:49+13:00]]} "G" 3729]
rec: [[gchat ["Test"] ["Graham" 0.145.0 "testing." 0.0.0 240.240.240 [] 7-Mar-2006/18:30:49+13:00]]]
}
                                                    if any [ channel/port/user-data/username = rec/1/3/1 group = rec/1/2/1 ][
                                                        append/only result rec/1
                                                    ]
                                                ]
                                                ; now we need to sort these messages in msgid...
                                                foreach r result [
                                                    post-msg1 channel mold/all r
                                                ]
                                            ]
                                ] [
                                    print "Database retrieve error"
                                    probe mold disarm err2
                                ]
                                post-msg1 channel mold/all reduce [
                                    'cmd
                                    reduce ['downloading 'finished]
                                ]
                            ] ;; end of message downlaod
                        ]
                        ;; end of database to fetch old messages

                        ;; set time zone


                        parse usercmd ['timezone set tzone time!] [
                            use [status ip-port ndx] [
                                ; ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                                ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                if found? ndx: find user-table ip-port [
                                    ndx/2/tz: form tzone
                                ]
                                ; now update everyone
                                update-room-status
                            ]
                        ]

                        parse usercmd ['language set lang [word!|string!]] [
                            use [status ip-port ndx] [
                                ; ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                                if found? ndx: find user-table ip-port [
                                    ndx/2/language: form lang
                                ]
                                ; now update everyone
                                update-room-status
                            ]
                        ]

                        parse usercmd ['status set userstate string!] [
                            ; user is altering their online status
                            use [status ip-port ndx] [
                                ; ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                                ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                if found? ndx: find user-table ip-port [
                                    ; ndx/3: copy userstate
                                    ndx/2/status: copy userstate
                                ]
                                ; now update everyone
                                update-room-status
                            ]
                        ]
                        parse usercmd ['login set nickname string!] [
                            ?? nickname
                            ; each user sends a login command with their username
                            ; we build up the list of active users that way
                            use [ip-port username ndx chat-users tmp] [
                                ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                                username: channel/port/user-data/username
                                ; now find the new user in the user-table
                                forskip user-table 2 [
                                    if user-table/2/username = channel/port/user-data/username [
                                        user-table/1: ip-port
                                        user-table/2/username: channel/port/user-data/username
                                        user-table/2/status: "login"
                                        break
                                    ]
                                ]

                                user-table: head user-table
                                comment {								
                                ; ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                                if found? ndx: find user-table ip-port [
                                    remove/part ndx 2
                                ]
                                ; repend user-table [ip-port nickname "active"]
                                tmp: make prefs-obj [
                                    username: nickname
                                    status: "login"
                                ]
                                repend user-table [
                                    ip-port tmp
                                ]
}
                                ; send a message to notify the lobby of new message
                                msg-to-all mold/all reduce [
                                    'gchat
                                    ["lobby"]
                                    reduce ["Hal4000" red
                                        rejoin [channel/port/user-data/username " has just entered the building."]
                                        black white [] now
                                    ]
                                ]
                                ; now send an update to everyone
                                update-room-status
                                ; now send a command to notify of new user
                                msg-to-all mold/all reduce [
                                    'cmd
                                    reduce ['arrived channel/port/user-data/username]
                                ]

                            ]
                            ; get Eliza to acknowledge the login
                            post-msg1 channel mold/all reduce [
                                'gchat
                                ["lobby"]
                                reduce ["Eliza" red
                                    rejoin ["Welcome " channel/port/user-data/username ". If you want to chat to me, address me by name."]
                                    black white [] now
                                ]
                            ]
                            if channel/port/user-data/username <> "Guest" [
                                insert db-port [{select longitude, latitude from users where userid = (?)} channel/port/user-data/username]
                                result: pick db-port 1
                                if any [none? result/1 none? result/2] [
                                    post-msg1 channel mold/all reduce [
                                        'gchat
                                        ["lobby"]
                                        reduce ["Eliza" red
                                            rejoin [channel/port/user-data/username " please enter your latitude and longitude data ( right click on your own name)."]
                                            black white [] now
                                        ]
                                    ]



                                ]]
                            ?? user-table
                        ]
                    ]

                ]

                parse clientmsg ['action set ip-ports block! set cmdblock block!] [
                    ; origin-ip-port: form rejoin [channel/port/sub-port/remote-ip ":" channel/port/sub-port/remote-port]
                    origin-ip-port: form rejoin [channel/port/user-data/remote-ip ":" channel/port/user-data/remote-port]
                    print ["cmd: " clientmsg]
                    ; case [
                    ; cmdblock/1 = "nudge" [
                    ; send a nudge to all the ip-ports
                    ; ?? ip-ports
                    foreach ip-port ip-ports [
                        if 2 = length? ip-port: parse/all ip-port ":" [
                            foreach channel chatroom-peers [
                                if all [ip-port/1 = form channel/port/user-data/remote-ip
                                    ip-port/2 = form channel/port/user-data/remote-port
                                ] [
                                    ; only send the action to those ip-ports listed
                                    post-msg1 channel mold/all reduce [
                                        'action
                                        reduce [cmdblock origin-ip-port]
                                    ]
                                    print ["Sending action to" ip-port]
                                    ;?? origin-ip-port

                                    ; should be a unique ip-port
                                    break
                                ]
                            ]
                        ]
                    ]
                    ; ]			
                    ; ]
                ]

                parse clientmsg ['gchat (ctype: "G") set userblock block! set clientmsg block!] [

                    ;chatroom-peers is empty for the initiator
                    ;this is only executed in the listener side
                    ; post-msg channel msg/payload

                    ; send the message immediately to all initiators
                    insert back back tail msg/payload now
                    ; msg-to-all msg/payload

                    ;; now save the message on the database.  not going to save Eliza's comments!
                    comment {
CREATE TABLE "CHAT"
(
  "MSGDATE"	 timestamp default 'NOW',
  "AUTHOR" varchar(80),
  "GROUP" varchar(80),
  "MSG"	 VARCHAR(8192) NOT NULL
);
SET TERM ^ ;
}

                    ; print "Want to insert this"
                    ; probe msg/payload

                    comment {
Want to insert this
{[gchat ["lobby"] ["Graham" 128.128.128 "this message is to be saved." 0.0.0 240.240.240 []17-Jan-2006/13:36:10+13:0
0]]}
}

                    ;;; remove this for no database storage

                    use [public-msg err2 txt maxmsgid payload] [
                        if error? set/any 'err2 try [
                            public-msg: load msg/payload
                            ; need to remove the text and save that separately so that can be searched on
                            txt: copy public-msg/3/3
                            ; and now we remove the txt from the message
                            public-msg/3/3: copy ""
                            insert db-port [{insert into CHAT ( author, CHANNEL, msg, format, ctype ) values (?, ?, ?, ?, ?) } public-msg/3/1 public-msg/2/1 txt public-msg ctype]
                            insert db-port {select max(msgid) from chat}
                            maxmsgid: pick db-port 1
                            ; ?? maxmsgid
                            ; probe msg/payload
                            comment {
maxmsgid: [4]
{[gchat ["lobby"] ["Graham" 140.0.0 "testing to see what the msgid is ..." 0.0.0 240.240.240
[]8-Mar-2006/14:19:34+13:00]]}							
}
                            payload: load msg/payload
                            insert tail payload/3 maxmsgid/1
                            ;; ?? payload

                            msg-to-all mold/all payload



                            print "Public message saved into chat table"
                        ] [
                            print "Insert chat message failed because..."
                            probe mold disarm err2
                            msg-to-all mold/all reduce ['gchat
                                ["lobby"]
                                reduce ["Hal4000" red rejoin ["Server error on insert: " mold disarm err2] black white [bold] now]
                            ]
                        ]
                    ]
                    ;; end remove of database storage					

                    print "stored .. now doing case"
                    ?? userblock
                    ?? clientmsg

                    if error? set/any 'err3 try [
                        case [
                            all [userblock/1 = "lobby" find/part clientmsg/3 "who is here" 11] [
                                use [chat-users] [
                                    chat-users: copy []
                                    foreach [ip-port name status] user-table [
                                        repend chat-users [name ip-port status]
                                        ; repend chat-users [chan/port/user-data/username chan/port/user-data/remote-ip chan/port/sub-port/remote-port]
                                    ]

                                    msg-to-all mold/all reduce ['gchat
                                        ["lobby"]
                                        reduce
                                        ["Hal4000" red rejoin ["Currently we have: " chat-users] black white [bold] now]
                                    ]
                                ]
                            ]

                            all [userblock/1 = "lobby" find/part clientmsg/3 "version?" 8] [
                                msg-to-all mold/all reduce ['gchat
                                    ["lobby"]
                                    reduce
                                    ["Hal4000" red "Message server version 0.0.19" black white [bold] now]
                                ]
                            ]

                            all [userblock/1 = "lobby" find/part clientmsg/3 "wakeup Eliza" 12] [
                                eliza-on: true
                                msg-to-all mold/all reduce ['gchat
                                    ["lobby"]
                                    reduce
                                    ["Eliza" red "Thanks for inviting me back." black white [] now]
                                ]
                            ]

                            all [userblock/1 = "lobby" find/part clientmsg/3 "sleep Eliza" 11] [
                                eliza-on: false
                                msg-to-all mold/all reduce ['gchat
                                    ["lobby"]
                                    reduce
                                    ["Eliza" red "I'm off for a nap.  Just wake me if you want to chat." black white [] now]
                                ]
                            ]

                            all [userblock/1 = "lobby" find/part clientmsg/3 "help Eliza" 11] [
                                eliza-on: false
                                msg-to-all mold/all reduce ['gchat
                                    ["lobby"]
                                    reduce
                                    ["Eliza" red "I recognize: wakeup Eliza, and sleep Eliza.^/Type Help in my channel for more help!" black white [] now]
                                ]
                            ]

                            all [userblock/1 = "lobby" any [eliza-on find/part clientmsg/3 "Eliza" 5]] [
                                if find/part clientmsg/3 "Eliza" 5 [
                                    if found? msg-to-eliza: find/tail clientmsg/3 " " [
                                        clientmsg/3: msg-to-eliza
                                    ]
                                ]

                                if error? try [
                                    eliza-says: copy match clientmsg/3
                                ] [
                                    eliza-says: "Oops, I just had a little petit mal aka parse error."
                                ]
                                msg-to-all mold/all reduce ['gchat
                                    ["lobby"]
                                    reduce
                                    ["Eliza" red rejoin [clientmsg/1 ", " eliza-says] black white [] now]
                                ]
                            ]

                            ; check to see if url hiding inside message, or, being asked to explicitly save the 
                            ; message.


                            any [
                                find clientmsg/3 "http"
                                find/part clientmsg/3 "save" 4
                                find clientmsg/3 "ftp://"
                                find clientmsg/3 "mailto:"
                            ] [
                                print "saving message"
                                append/only chat-links load msg/payload
                                attempt [
                                    save/all %chat-links.r chat-links
                                ]
                            ]

                        ]
                    ] [
                        msg-to-all mold/all reduce ['gchat
                            ["Bugs"]
                            reduce
                            ["Hal4000" red rejoin [mold disarm err3] black snow [bold] now]
                        ]
                    ]

                    true [
                        ; unrecognised message format from client

                    ]
                ]
            ]

        ]

        ; set the read-rpy handler
        channel/read-rpy: func [
            {handle incoming replies}
            channel
            rpy
        ] [
            ;print "read-rpy handler of PUBTALK-ETIQUETTE" print mold rpy
            ;display rpy
            ;if rpy/payload <> 'ok [display/lost rpy]
        ]

        ; set the close handler
        channel/close: func [
            {to let the profile know, that the channel is being closed}
            channel
        ] [
            cleanup-chatroom channel
        ]
    ]
    ; profile helper functions
    ack-msg: func [channel] [
        send-frame/callback channel make frame-object [
            msgtype: 'RPY
            more: '.
            payload: to binary! "ok"
        ] [; print "RPY sent"
        ]
    ]

    reply-query: func [channel from msg] [
        post-msg1 channel mold/all reduce ['gchat ["lobby"] reduce [from red msg black white [] now]]
    ]

    set 'post-msg func [channel msg] [
        send-frame/callback channel make frame-object [
            msgtype: 'MSG
            more: '.
            payload: to binary! :msg
        ] [; print "call to callback"
        ]
    ]

    set 'post-msg1 func [channel msg] [
        send-frame channel make frame-object [
            msgtype: 'MSG
            more: '.
            payload: to binary! :msg
        ]
    ]

    set 'cleanup-chatroom func [channel] [
        ;keep the house clean, erase peer from chatroom-peers 
        remove-each peer chatroom-peers [:peer = :channel]
    ]

    set 'cmd-to-all func [instruction data] [
        ; send a command message to everyone in the chatroom-peers
        foreach chan chatroom-peers [
            post-msg1 chan mold/all reduce ['cmd reduce [instruction data]]
        ]
    ]

    set 'msg-to-all func [msg] [
        ; send a text messaget to everyone in the chatroom-peers
        foreach channel chatroom-peers [
            post-msg1 channel msg
        ]
    ]

    set 'sent-to-user func [ addressee msg ][
        foreach channel chatroom-peers [
            if channel/port/user-data/username = addressee [
                post-msg1 channel msg
                ; break
            ]
        ]
    ]

    set 'update-room-status func [/local chat-users tmp] [
        chat-users: copy []
        ; ?? user-table
        foreach [ip-port prefsobj] user-table [
            ip-port: form ip-port
            ; print ["ip-port" ip-port]
            tmp: make object! [
                city: prefsobj/city
                tz: prefsobj/tz
                email: prefsobj/email
                longitude: prefsobj/longitude
                latitude: prefsobj/latitude
            ]
            either find ip-port ":" [
                ip-port: parse/all ip-port ":"
                repend chat-users [
                    prefsobj/username
                    prefsobj/status
                    ip-port/1 ip-port/2
                    tmp
                ]
                ; print "Added name and object"
            ] [
                print ["bad ip port" ip-port]
            ]
        ]
        cmd-to-all 'set-userstate chat-users
    ]

]


;set path for received files

ft-profile: profile-registry/filetransfer
if ft-profile/destination-dir: %chat-uploads/ [make-dir ft-profile/destination-dir]


file-list: copy []
file-keys: make hash! []

debug: :none

;set callback handler for POST on server
ft-profile/post-handler: [
    switch action [
        init [
        ]
        read [
        ]
        write [
            ;renaming/filexists? routine
            if not exists? join data/7 channel/port/user-data/username [
                attempt [
                    make-dir/deep join data/7 channel/port/user-data/username
                ]
            ]

                    new-name: second split-path data/3
            either  exists? to-file rejoin [ data/7 channel/port/user-data/username "/" new-name ][
                print "file exists! changing name..."
                nr: 0
                until [
                    nr: nr + 1
                    either find tmp-name: copy new-name "." [
                        insert find/reverse tail tmp-name "." rejoin ["[" nr "]"]
                    ][
                        insert tail tmp-name rejoin ["[" nr "]"]
                    ]
                    tmp-name: replace/all tmp-name "/" ""
                    not exists? to-file rejoin [ data/7 channel/port/user-data/username "/" tmp-name ]
                ]
                new-name: to-file rejoin [ channel/port/user-data/username "/" tmp-name ]
            ][
                new-name: to-file rejoin [ channel/port/user-data/username "/" new-name ]
            ]

            print ["rename" join data/7 data/1 "to" new-name ]
            if error? set/any 'err try [
                change-dir data/7
                ; PROBE (to-file DATA/1)
                ; PROBE  NEW-NAME
                rename (to-file data/1) new-name
                change-dir %../
            ][
                print "Renaming failed"
                probe mold disarm err
            ]

            msg-to-all mold/all reduce [
                'gchat
                ["Files"]
                reduce ["Hal4000" red
                rejoin [ form last split-path new-name " has just been uploaded by " channel/port/user-data/username]
                black white [] now
                ]
            ]
            attempt [
                probe channel/port/user-data/username
            ]

;; save into database
        ]
        error []
    ]
]
ft-profile/get-handler: func [channel action data][
        switch action [
            init [
 ;               print ["start sending file" data/3 "of size" data/5 "to listener."]
            ]
            read [
 ;               print ["sending datachunk of file" data/3 "of size" data/6 "bytes"]
            ]
            write [
                print ["file" data/3 "has been completely sent to initiator"]
            ]
        ]
    ]

#include %/c/rebol/rebgui/beer2/beer/authenticate.r
;#include %/c/rebol/rebgui/beer/examples/encoding-salt.r

if now/date > expiry_date [
    view center-face layout [
        info "This beta server version is too old! Check the website for a more recent version of chat-server.exe" red wrap 200x60
        btn "Website Downloads" [ browse http://www.compkarori.com/reb/chat-server.exe ]
    ]
    quit
]
digit: charset "0123456789"
ip-rule: [1 3 digit "." 1 3 digit "." 1 3 digit "." 1 3 digit ":" 2 4 digit]


default-user: make object! [
    name: "Portal Administrator"
    email: no-one@nowhere.com
    smtp: none
    timezone: now/zone
    port: 8012
    database: "chat"
    admin: "SYSDBA"
    pass: "masterkey"
]

userobj: default-user

    either not none? args [
        if not empty? args [
;			attempt [
                either all [1 = length? args exists? input-file: to-rebol-file to-file first args] [
                    ; args: parse read input-file none
                        command-line: load input-file
                ] [

                    tmp: copy ""
                    foreach arg args [
                        either parse arg ip-rule
                        [repend tmp [{"} arg {" }]]
                        [
                            repend tmp [arg " "]
                        ]
                    ]
                    command-line: load tmp
                ]
                if word! = type? command-line [
                    tmp: command-line
                    command-line: copy []
                    append command-line tmp
                ]
;			]
        ]
;		PROBE ARGS
;		PROBE COMMAND-LINE
        user:
        pass:
        port:
        dsn:    
        none

; [-port 8012 -user Sysdba -pass masterkey -dsn chat ]

        cmd-rule: [some [
                '-port set port integer! |
                '-user set user [ word! | string!] |
                '-dsn set dsn [ word! | string! ] |
                '-pass set pass [ word! | string! ]
                ]
        ]
        if error? set/any 'err try [parse command-line cmd-rule] [

            errtitle/text: "An error occurred in the command line or drag and dropped file."
            errmsg/text: err: mold disarm err
            inform errlo
            quit
        ]
        ;; parsed the command line correctly
        if any [ none? port none? user none? pass none? dsn ][
            alert "Not all parameters given on command line or file"
            quit        
        ]     

        database-string: to-url rejoin [ odbc:// userobj/admin ":" userobj/pass "@" userobj/database ] ; SYSDBA:masterkey@chat
        userobj/admin: form user
        userobj/pass: form pass
        userobj/database: form dsn
        userobj/port: port
    ] [view center-face layout compose/deep [
        style lab text bold 90 right
        across
        vh2 "Configure Chat Server" red return
        lab "ODBC DSN:" dns: field (userobj/database) 100 return
        lab "Username:" dns-username: field (userobj/admin) 100 return
        lab "Password:" dns-password: field (userobj/pass) 100 return
        lab " Port No:" dns-port: field (form userobj/port) 40 return
        pad 100 btn "Start" [
            if error? try [
                userobj/admin: trim dns-username/text
                userobj/pass: trim dns-password/text
                userobj/database: trim dns/text
                userobj/port: to-integer trim dns-port/text
            ][
                alert "Error in settings"
                return
            ]

            if error? try [
                tmp: open to-url join "tcp://:" userobj/port
                close tmp
            ][
                alert "This port is in use"
                return
            ]

            unview
        ]
        btn "Quit" [ Quit ]
    ]
]

database-string: to-url rejoin [ odbc:// userobj/admin ":" userobj/pass "@" userobj/database ] ; SYSDBA:masterkey@chat

alter-coordinates: has [ result ][
    result: false
    insert db-port [ 'columns "USERS" ]
    foreach record copy db-port [
        if all [ record/4 = "LATITUDE" record/9 = 0 ][
            result: true
        ]
    ]
    if result [
        insert db-port {alter table users alter longitude type decimal(9,3)}
        insert db-port {alter table users alter latitude type decimal(9,3)}
        print "Coordinate fields updated"
    ]
]

alter-msgdate: has [result][
    insert db-port {select msgdate from chat where msgid = 1}
    result: pick db-port 1
    if none? result [ return ]
    if none? result/1 [
        if request {This appears to be the old chat database downloaded before 8th March 06. We need to update all the msgdate fields.  Proceed?} [
            insert db-port {alter table chat drop msgdate}
            insert db-port {alter table chat add msgdate timestamp default 'NOW'}
            ; insert db-port {update chat set msgdate = 'NOW'}
            insert db-port {update chat set msgdate = 'NOW' where msgdate is null }
            print "Chat table msgdate field updated"
        ]
    ]
]
do OpenODBC: does [
    if error? set/any 'err try [
        dbase: open database-string
        db-port: first dbase

        alter-coordinates
        alter-msgdate

    ][
                    probe mold disarm err
        ; print "Fatal error - unable to open odbc connection to remr database"
        ; halt
        view center-face layout [
            across
            h1 "Synapse Chat Server" red return
            h2 "First Time Install?" return
            info  
{This screen has appeared as we can not open a connection to the database.

This could be because another copy of the program is running, or you have an incorrect database, admin, password combination, or you have yet to install the Synapse Chat Server, 

If the latter is correct, you need to download the Firebird Database software, the Firebird ODBC connector, and the chat database.
} 350x180 wrap return
            pad 250 btn "Proceed" [ unview ] btn "Quit" [ quit ]

        ]
        view center-face layout [
        across
        h1 "Installation Instructions" red return
        info
{You must download and install the Firebird RDBMS.  As of 26-Feb-2006, the stable download is v.1.5.3*, and is dated 24-Jan-2006.  When you run the install program, you should choose the SuperServer install.

You must download and install the Firebird OBDC driver.  The latest stable release is version 1.2 dated 26-Aug-2004.  Choose the Windows full install.

You must note where you put the database download. You will need to reference this location when you create the ODBC connector.  The file should be in a directory you can easily backup.

We shall assume that you will put in into c:\chat\

The buttons below will take you to the download pages. Click on the "Proceed" button after you have download all files, and installed both Firebird packages.  
}  450x270 wrap

return
        btn "Firebird RDBMS (2.7 Mb)" [ browse http://www.firebirdsql.org/index.php?op=files&id=engine ] 
        text "Firebird-1.5.2.4731-Win32.exe" bold
        return
        btn "Firebird ODBC (596 kbs)" [ browse http://www.firebirdsql.org/index.php?op=files&id=odbc ] 
        text "Firebird_ODBC_1.2.0.69-Win32.exe" bold
        return
        btn "Empty Database (636 kbs)" [ browse http://www.compkarori.com/reb/CHAT.FDB ]
        text "CHAT.FDB" bold 
        pad 120 btn "Proceed" [ Unview ] btn "Quit" [ quit]
        ]        

        view center-face layout [
            across
            h1 "Creating the ODBC connection" red return
            info 
{Now that you have sucessfully installed the Firebird SuperServer, and the Firebird ODBC driver, you now need to create the ODBC connection that will allow Synapse Chat to talk to the database.

The following assumes that you have saved the database file "CHAT.FDB" into the directory C:\chat\, but if you have not, substitute your own path.

You now need to open up the "Data Sources (ODBC)". In Windows XP, this is reached from the Control Panel, and then "Administrative Tools".  In Windows 2003 Server, "Administrative Tools" is available from the Start Menu.

With the "Data Sources (ODBC) Administrator" open, you should see the "Firebird/Interbase(r) driver" listed in the drivers tab (Screenshot 1).  If not, then you need to reinstall the Firebird ODBC driver.

Select the "System DSN" tab (DSN = Data source name), and then click on the "Add" button.  Select the "Firebird/Interbase(r) driver" (Screenshot 2) and then the "Finish" button.

(Screenshot 3) In the "Data Source Name (DSN)" field, enter "chat".  In the "Database" field, enter "C:\chat\CHAT.FDB" or the appropriate path.  You can use the "Browse" button to put the file into the field.  Leave the "Client" field empty.  Enter "SYSDBA" in the "Database Account" field, and "masterkey" in the "Password" field.  Try the "Test Connection" button to check if it is working.  If it is, then click on "OK" to save it.  You are now ready to proceed further to a restart.  If the same install screens appear, then you have not successfully completed the preceding steps.

With luck, you will see a screen to add the admin user (Screenshot 4), and once that is done, you should be up and running (Screenshot 5).

NB: You need to make sure that your firewall is blocking TCP port 3050 so that no-one outside your network can access your Firebird server.
}  600x450 wrap return
btn "Screenshot 1" [ view/new layout [ across image driver.jpg return btn "Close" keycode [#"^["] [unview]]]
btn "Screenshot 2" [ view/new layout [ across image select.jpg return btn "Close" keycode [#"^["] [unview]]]
btn "Screenshot 3" [ view/new layout [ across image odbc.jpg return btn "Close" keycode [#"^["] [unview]]] 
btn "Screenshot 4" [ view/new layout [ across image admin.jpg return btn "Close" keycode [#"^["] [unview]]]
btn "Screenshot 5" [ view/new layout [ across image running.jpg return btn "Close" keycode [#"^["] [unview]]]
pad 60 btn "Proceed" [ launch/quit ""] btn "Quit" [quit]
        ]
    quit
    ]
]

stopODBC: does [
    close db-port
    close dbase
]	 

restartODBC: has [ err ] [
    if error? set/any 'err try [
        attempt [ stopODBC ]
        recycle
        openODBC
        return "Restarted ODBC"
    ][ print mold disarm err return "Error on restarting ODBC" ]
]

insert db-port {select count('uid') from users}
no_of_staff: pick db-port 1
no_of_staff: pick no_of_staff 1

if no_of_staff = 0 [
    view center-face layout [
        across
        title "Set Up Admin User" red return space 1x1
        text "Username" bold 80 adminfld: field 80x20 font [size: 11] return
        text "Password" bold 80 passfld: field 80x20 font [size: 11] text {(minimum 8 characters)} return
        text "Given Name" bold 80 fnamefld: field 160x20 font [size: 11] return
        text "SurName" bold 80 snamefld: field 160x20 font [size: 11] return space 5x5
        text "Gender" bold 80 genderfld: field "M" 20x20 font [size: 11] return
        text "Email" bold 80 emailfld: field 200x20 font [size: 11] return
        text "Secret Question" bold 80 secretfld: field 200x20 font [size: 11] return
        text "Answer" bold 80 answerfld: field 200x20 font [size: 11] return
        pad 100 btn "Create" [
            either all [ not empty? adminfld/text not empty? passfld/text not empty? fnamefld/text not empty? snamefld/text not empty? genderfld/text not empty? secretfld/text not empty? answerfld/text (length? passfld/text) > 7 ][

                insert db-port [{insert into USERS (userid, rights, fname, surname, reminder, answer, email, gender, pass, activ ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)} adminfld/text 5 fnamefld/text snamefld/text secretfld/text answerfld/text emailfld/text genderfld/text form encode-pass passfld/text encoding-salt "T"]
              unview
            ][
                alert "All fields need to be filled in and password is 8 characters or more"
            ]
        ] 
        btn "Quit" [ quit ] 
        do [ focus adminfld ]
    ]
]

    add-user: [
        across
        title "Set Up User" red return space 1x1
        text "Username" bold 80 adminfld: field 80x20 font [size: 11] return
        text "Password" bold 80 passfld: field 80x20 font [size: 11] text {(minimum 8 characters)} return
        text "Given Name" bold 80 fnamefld: field 160x20 font [size: 11] return
        text "SurName" bold 80 snamefld: field 160x20 font [size: 11] return space 5x5
        text "Gender" bold 80 genderfld: field "M" 20x20 font [size: 11] text "(Email used for password recovery)" return
        text "Email" bold 80 emailfld: field 200x20 font [size: 11] return
        text "Secret Question" bold 80 secretfld: field 200x20 font [size: 11] return
        text "Answer" bold 80 answerfld: field 200x20 font [size: 11] return
        pad 100 btn "Create" [
            either all [ not empty? adminfld/text not empty? passfld/text not empty? fnamefld/text not empty? snamefld/text not empty? genderfld/text not empty? secretfld/text not empty? answerfld/text (length? passfld/text) > 7 ][

                if error? set/any 'err try [
                    insert db-port [{insert into USERS (userid, rights, fname, surname, reminder, answer, email, gender, pass, pwd ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)} adminfld/text 0 fnamefld/text snamefld/text  secretfld/text answerfld/text emailfld/text genderfld/text form encode-pass passfld/text encoding-salt passfld/text]
                    unview
                ][
                    probe mold err: disarm err

                    if find err/arg2 "violation of PRIMARY or UNIQUE KEY" [
                        print "This username is already in use"
                    ]
                    print "A sql error occurred - see console for explanation"
                ]              
            ][
                print "Fill in all fields according to criteria and password length"
            ]
        ] 
        btn "Close" keycode [ #"^["] [ unview ] 
        do [ focus adminfld ]
    ]

groups: load [
root [
    echo []
    filetransfer []
    rpc []
    PUBTALK-ETIQUETTE []
]

admin [
    echo []
]

chatuser [
    echo []
    filetransfer []
    rpc [register-user get-dir file-exists? fetch-message]
    PUBTALK-ETIQUETTE []
]

anonymous [
    echo []
    rpc [register-user]
    PUBTALK-ETIQUETTE []    
]
]

do build-userfile: has [ security ][
    users: load {"anonymous" #{} nologin [anonymous]
    "listener" #{} nologin [monitor]
    "root" #{F71C2F645E81504EB9CC7AFC35C7777993957B4D} login [root]
    }

    insert db-port {select userid, pass, rights from users where activ = 'T'}

    foreach record copy db-port [

        switch/default record/3 [
            0 [ security: to-word "anonymous" ]
            1 [ security: to-word "chatuser" ]
            5 [ security: to-word "root" ]
        ][ security: to-word "root" ]
        repend users compose/deep [ record/1 load record/2 'login [ (security) ]  ]

    ]
]

attempt [
view/new layout compose [
    across
    h1 "Synapse Chat control panel" red return
    h2 "Server: " text (userobj/database) return
    btn "Shut down" [ stopODBC quit ] btn "Add User" [ view/new center-face layout add-user ]
    btn "Reload Users" [build-userfile] return
    btn "Enable Guest" [
        if error? set/any 'err try [
        insert db-port [{insert into USERS (userid, rights, fname, surname, reminder, answer, email, gender, pass, pwd ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)} "Guest" 0 "Guest" "Guest"  "" "" "" "" form encode-pass "Guest123" encoding-salt "Guest123"]
        ][
            err: disarm err

            either find err/arg2 "violation of PRIMARY or UNIQUE KEY" [
                print "Guest account is already enabled"
            ][
                print mold err
            ]
        ]
    ]
    return
    info {Be sure to use the "Shut down" button in this control panel to avoid database corruption.  Closing this window, or the console, in any other way may have unpredictable effects on the database.  Both will shut the server down.^/You need to enable the guest account if you wish to allow remote users to register.} 250x170 wrap
]
]



#include %/c/rebol/rebgui/shrink.r
case: func [[throw catch]
    {
        Polymorphic If
        lazy evaluation
        no default (use True guard instead)
        If/Either compatibility:
            guard checking (unset not allowed)
            non-logic guards allowed
            block checking (after a guard only a block allowed)
            computed blocks allowed
            Return working
            Exit working
            Break working
    }
    args [block!] /local res
] [
    either unset? first res: do/next args [
        if not empty? args [
            ; invalid guard
            throw  make error! [script no-arg case condition]
        ]
    ] [
        either first res [
            either block? first res: do/next second res [
                do first res
            ] [
                ; not a block
                throw make error! [
                    script expect-arg case block [block!]
                ]
            ]
        ] [
            case second do/next second res
        ]
    ]
]



; sessions: copy []
timeout: 00:20:00 ; 20 mins
ftimeout: 00:05:00 ; 5 mins
invalid-session: "Logged out due to inactivity"

fileCache: copy []

session-object: make object! [ sessionid: userid: timestamp: ipaddress: security: lastmsg:  none ]

print [ "Synapse Chat Server " server-version " serving .... on port " userobj/port ]
; enterLog "Restart" "Admin" "Normal start"

basic-service: make-service [
    info: [
        name: "basic services"
    ]
    services: [time info registration maintenance]
    data: [
        info [
            service-names: func []	[
                services
            ]
        ]
        time [
            get-time: func []	[
                    now/time
            ]
        ]
        registration [
            register-user: func [ userid pass fname sname gender email secret answer 
                /local err result 
            ][
                print [ userid pass fname sname gender email secret answer  ]
                if error? set/any 'err try [
                    pwd: form encode-pass pass encoding-salt
                    activ: "F"
                    insert db-port [{insert into USERS (userid, rights, fname, surname, reminder, answer, email, gender, pass, activ, pwd ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)} userid 1 fname sname secret answer email gender pwd  "F" pass]
                    attempt [
                            send compkarori@gmail.com join "New user registration on Synapse Chat: " userid
                    ]
                    attempt [
                        send/subject to-email email 
                            rejoin [ "You registered with the chat server as follows - user: " userid " password: " pass "^/both if which are case sensitive. ^/You will be contacted once your account is enabled." ] {Chat registration details}
                    ]
                    return reduce [ true ]
                ][ 
                    probe mold err: disarm err

                    if find err/arg2 "violation of PRIMARY or UNIQUE KEY" [
                        return [ -1 "This username is in use" ]
                    ]
                    return [ -1 "sql error in add-user" ]
                ]
            ]

        ]

        maintenance [
            show-users: func [/local result][
                result: copy []
                insert db-port {select uid, userid, fname, surname, email, activ from users}
                foreach record copy db-port [
                    append/only result record
                ]
                return result
            ]

            delete-user: func [ uid [integer!] ][
                insert db-port [{delete from users where uid = (?)} uid ]
                return true
            ]
            disable-user: func [ uid [integer!] ][
                insert db-port [{update users set activ = 'F' where uid = (?)} uid ]
                return true
            ]
            enable-user: func [ uid [integer!] ][
                insert db-port [{update users set activ = 'T' where uid = (?)} uid ]
                return true
            ]
            update-password: func [ uid password ][
                insert db-port [{update users set pass = (?), pwd = (?) where uid = (?)} encode-pass password encoding-salt password uid ]
                return true
            ]
            rebuild-users: does [
                build-userfile
                return true
            ]

            restart-server: does [
                print "Client requesting a server restart"
                close db-port
                close dbase
                ; call {rebcmdview.exe -s chat-server.r}
                ; quit
                launch/quit rejoin [ "-user " userobj/admin " -pass " userobj/pass " -port " userobj/port " -dsn " userobj/database ]
            ]

            get-dir: func [ dir [file!] /local files filedata][
                probe dir
                either dir = %./
                [ files: read dir: ft-profile/destination-dir]
                [
                    if error? try [
                        probe  join ft-profile/destination-dir second split-path clean-path dir
                        files: read dir: join ft-profile/destination-dir second split-path clean-path dir
                    ][
                        files: copy []
                    ]
                ]
                filedata: copy []
                foreach file files [
                    inf: info? join dir  file
                    repend/only filedata [file inf/size inf/date]
                ]
                return filedata
            ]
            file-exists?: func [ file ][
                return either exists? to-file join %chat-uploads/ file [ true ] [ false ]
            ]
            delete-file: func [filename][
                either exists? join %chat-uploads/ filename [
                     if error? try [
                        delete join %chat-uploads/ filename
                        return "File deleted"
                     ][
                        return "Unable to delete file"
                     ]

                ][
                    return "File does not exist"
                ]
            ]
            fetch-message: func [ msgno [integer!] /local result][
                insert db-port [{select msg from chat where msgid=(?)} msgno ]
                result: pick db-port 1
                return result/1    
            ]
        ]
    ]
]

publish-service basic-service

; This is for the 'L side:

; chat-users: copy []

open-listener/callback userobj/port func [peer] [
    use [remote-ip remote-port peer-port ip-port] [

        print ["New mate on the bar" peer/sub-port/remote-ip peer/sub-port/remote-port]
        peer-port: :peer
        peer/user-data/on-close: func [msg /local channel] [
            print ["Mate left" peer-port/user-data/username peer-port/user-data/remote-ip peer-port/user-data/remote-port "reason:" msg]
            ; clean up by removing disconnected clients
            msg-to-all mold/all reduce ['gchat
                                        ["lobby"]
                                        reduce
                                        ["Hal4000" red rejoin [peer-port/user-data/username " has just left the building"] black white [] now]
                                    ]
            if error? set/any 'err try [                       
                insert db-port [ {update USERS set laston = 'NOW' where userid = (?)} peer-port/user-data/username ]            
            ][
                probe mold disarm err
            ]            
            print ["before removal users: " length? chatroom-peers]
                use [chat-users temp-table] [
                ; first remove disconnected clients 
                forall chatroom-peers [
                    if chatroom-peers/1/port/locals/peer-close [
                        remove chatroom-peers
                    ]
                ]
                rebuild-user-table
            ]
        ]
    ]
]

do-events






