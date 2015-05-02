express = require 'express'
bodyParser = require 'body-parser'
dotenv = require 'dotenv'

SpotifyWebApi = require 'spotify-web-api-node'
Slack = require 'slack-node'

dotenv.load()

spotifyApi = new SpotifyWebApi({
  clientId: process.env.SPOTIFY_KEY,
  clientSecret: process.env.SPOTIFY_SECRET,
  redirectUri: process.env.SPOTIFY_REDIRECT_URI
})

slack = new Slack()
slack.setWebhook(process.env.SLACK_WEBHOOK_URL)

app = express()
app.use bodyParser.json()
app.use(bodyParser.urlencoded({
  extended: true
}))

app.get '/', (req, res) ->
  if spotifyApi.getAccessToken()
    res.send 'You are logged in.'
  else
    res.send '<a href="authorize">Authorize Spotify Account</a>'

app.get '/authorize', (req, res) ->
  scopes = ['playlist-modify-public', 'playlist-modify-private']
  state = new Date().getTime()
  authorizeURL = spotifyApi.createAuthorizeURL(scopes, state)
  res.redirect(authorizeURL)

app.get '/callback', (req, res) ->
  spotifyApi.authorizationCodeGrant(req.query.code)
    .then (data) ->
      spotifyApi.setAccessToken data.body['access_token']
      spotifyApi.setRefreshToken data.body['refresh_token']
      res.redirect '/'
    ,(err) ->
      res.send(err)

app.use '/store', (req, res, next) ->
  if (req.body.token != process.env.SLACK_TOKEN)
    res.status(500).send('Access forbidden.')
  next()

app.post '/store', (req, res) ->
  spotifyApi.refreshAccessToken()
    .then (data) ->
      spotifyApi.searchTracks req.body.text
        .then (data) ->
          results = data.body.track.items
          if results.length is 0
            return res.send 'Could not find that track.'
          track = results[0]
          spotifyApi.addTracksToPlaylist process.env.SPOTIFY_USERNAME, process.env.SPOTIFY_PLAYLIST_ID, ["spotify:track:#{track.id}"]
            .then (data) ->
              artistName = track.artists[0].name
              trackName = track.name
              slack.webhook {
                channel: '#jaystu_sandbox'
                username: 'jukebot'
                text: "Track #{trackName} by #{artistName} was added to playlist."
              }, (err, response) ->
                console.log response

              console.log "Track added."

            , (err) ->
              res.send err.message
          , (err) ->
            res.send err.message
        , (err) ->
          res.send err.message




app.set 'port', process.env.PORT || 5000
app.listen app.get('port')