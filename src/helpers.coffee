{calculateSpecificity} = require 'clear-cut'
KeyboardLayout = require 'keyboard-layout'

MODIFIERS = new Set(['ctrl', 'alt', 'shift', 'cmd'])
ENDS_IN_MODIFIER_REGEX = /(ctrl|alt|shift|cmd)$/
WHITESPACE_REGEX = /\s+/
NON_CHARACTER_KEY_NAMES_BY_KEYBOARD_EVENT_KEY = {
  'Control': 'ctrl',
  'Meta': 'cmd',
  'ArrowDown': 'down',
  'ArrowUp': 'up',
  'ArrowLeft': 'left',
  'ArrowRight': 'right'
}
MATCH_TYPES = {
  EXACT: 'exact'
  KEYDOWN_EXACT: 'keydownExact'
  PARTIAL: 'partial'
}

isASCIICharacter = (character) ->
  character? and character.length is 1 and character.charCodeAt(0) <= 127

isLatinCharacter = (character) ->
  character? and character.length is 1 and character.charCodeAt(0) <= 0x024F

isUpperCaseCharacter = (character) ->
  character? and character.length is 1 and character.toLowerCase() isnt character

isLowerCaseCharacter = (character) ->
  character? and character.length is 1 and character.toUpperCase() isnt character

usKeymap = null
usCharactersForKeyCode = (code) ->
  usKeymap ?= require('./us-keymap')
  usKeymap[code]

exports.normalizeKeystrokes = (keystrokes) ->
  normalizedKeystrokes = []
  for keystroke in keystrokes.split(WHITESPACE_REGEX)
    if normalizedKeystroke = normalizeKeystroke(keystroke)
      normalizedKeystrokes.push(normalizedKeystroke)
    else
      return false
  normalizedKeystrokes.join(' ')

normalizeKeystroke = (keystroke) ->
  if isKeyup = keystroke.startsWith('^')
    keystroke = keystroke.slice(1)
  keys = parseKeystroke(keystroke)
  return false unless keys

  primaryKey = null
  modifiers = new Set

  for key, i in keys
    if MODIFIERS.has(key)
      modifiers.add(key)
    else
      # only the last key can be a non-modifier
      if i is keys.length - 1
        primaryKey = key
      else
        return false

  if isKeyup
    primaryKey = primaryKey.toLowerCase() if primaryKey?
  else
    modifiers.add('shift') if isUpperCaseCharacter(primaryKey)
    if modifiers.has('shift') and isLowerCaseCharacter(primaryKey)
      primaryKey = primaryKey.toUpperCase()

  keystroke = []
  if not isKeyup or (isKeyup and not primaryKey?)
    keystroke.push('ctrl') if modifiers.has('ctrl')
    keystroke.push('alt') if modifiers.has('alt')
    keystroke.push('shift') if modifiers.has('shift')
    keystroke.push('cmd') if modifiers.has('cmd')
  keystroke.push(primaryKey) if primaryKey?
  keystroke = keystroke.join('-')
  keystroke = "^#{keystroke}" if isKeyup
  keystroke

parseKeystroke = (keystroke) ->
  keys = []
  keyStart = 0
  for character, index in keystroke when character is '-'
    if index > keyStart
      keys.push(keystroke.substring(keyStart, index))
      keyStart = index + 1

      # The keystroke has a trailing - and is invalid
      return false if keyStart is keystroke.length
  keys.push(keystroke.substring(keyStart)) if keyStart < keystroke.length
  keys

exports.keystrokeForKeyboardEvent = (event) ->
  {ctrlKey, altKey, shiftKey, metaKey} = event
  isNonCharacterKey = event.key.length > 1

  if isNonCharacterKey
    key = NON_CHARACTER_KEY_NAMES_BY_KEYBOARD_EVENT_KEY[event.key] ? event.key.toLowerCase()
  else
    key = event.key

    if altKey
      if process.platform is 'darwin'
        # When the option key is down on macOS, we need to determine whether the
        # the user intends to type an ASCII character that is only reachable by use
        # of the option key (such as option-g to type @ on a Swiss-German layout)
        # or used as a modifier to match against an alt-* binding.
        #
        # We check for event.code because test helpers produce events without it.
        if event.code and (characters = KeyboardLayout.getCurrentKeymap()[event.code])
          if shiftKey
            nonAltModifiedKey = characters.withShift
          else
            nonAltModifiedKey = characters.unmodified

          if not ctrlKey and not metaKey and isASCIICharacter(key) and key isnt nonAltModifiedKey
            altKey = false
          else
            key = nonAltModifiedKey
      else
        altKey = false if event.getModifierState('AltGraph')

  # Use US equivalent character for non-latin characters in keystrokes with modifiers
  # or when using the dvorak-qwertycmd layout and holding down the command key.
  if (not isLatinCharacter(key) and (ctrlKey or altKey or metaKey)) or
     (metaKey and KeyboardLayout.getCurrentKeyboardLayout() is 'com.apple.keylayout.DVORAK-QWERTYCMD')
    if characters = usCharactersForKeyCode(event.code)
      if event.shiftKey
        key = characters.withShift
      else
        key = characters.unmodified

  keystroke = ''
  if key is 'ctrl' or ctrlKey
    keystroke += 'ctrl'

  if key is 'alt' or altKey
    keystroke += '-' if keystroke.length > 0
    keystroke += 'alt'

  if key is 'shift' or (shiftKey and (isNonCharacterKey or (isLatinCharacter(key) and isUpperCaseCharacter(key))))
    keystroke += '-' if keystroke
    keystroke += 'shift'

  if key is 'cmd' or metaKey
    keystroke += '-' if keystroke
    keystroke += 'cmd'

  unless MODIFIERS.has(key)
    keystroke += '-' if keystroke
    keystroke += key

  keystroke = normalizeKeystroke("^#{keystroke}") if event.type is 'keyup'
  keystroke

exports.characterForKeyboardEvent = (event) ->
  event.key unless event.ctrlKey or event.metaKey

exports.calculateSpecificity = calculateSpecificity

exports.isBareModifier = (keystroke) -> ENDS_IN_MODIFIER_REGEX.test(keystroke)

exports.keydownEvent = (key, options) ->
  return buildKeyboardEvent(key, 'keydown', options)

exports.keyupEvent = (key, options) ->
  return buildKeyboardEvent(key, 'keyup', options)

buildKeyboardEvent = (key, eventType, {ctrl, shift, alt, cmd, keyCode, target, location}={}) ->
  ctrlKey = ctrl ? false
  altKey = alt ? false
  shiftKey = shift ? false
  metaKey = cmd ? false
  bubbles = true
  cancelable = true

  event = new KeyboardEvent(eventType, {
    key, ctrlKey, altKey, shiftKey, metaKey, bubbles, cancelable
  })

  if target?
    Object.defineProperty(event, 'target', get: -> target)
    Object.defineProperty(event, 'path', get: -> [target])
  event

# bindingKeystrokes and userKeystrokes are arrays of keystrokes
# e.g. ['ctrl-y', 'ctrl-x', '^x']
exports.keystrokesMatch = (bindingKeystrokes, userKeystrokes) ->
  userKeystrokeIndex = -1
  userKeystrokesHasKeydownEvent = false
  matchesNextUserKeystroke = (bindingKeystroke) ->
    while userKeystrokeIndex < userKeystrokes.length - 1
      userKeystrokeIndex += 1
      userKeystroke = userKeystrokes[userKeystrokeIndex]
      isKeydownEvent = not userKeystroke.startsWith('^')
      userKeystrokesHasKeydownEvent = true if isKeydownEvent
      if bindingKeystroke is userKeystroke
        return true
      else if isKeydownEvent
        return false
    null

  isPartialMatch = false
  bindingRemainderContainsOnlyKeyups = true
  bindingKeystrokeIndex = 0
  for bindingKeystroke in bindingKeystrokes
    unless isPartialMatch
      doesMatch = matchesNextUserKeystroke(bindingKeystroke)
      if doesMatch is false
        return false
      else if doesMatch is null
        # Make sure userKeystrokes with only keyup events doesn't match everything
        if userKeystrokesHasKeydownEvent
          isPartialMatch = true
        else
          return false

    if isPartialMatch
      bindingRemainderContainsOnlyKeyups = false unless bindingKeystroke.startsWith('^')

  # Bindings that match the beginning of the user's keystrokes are not a match.
  # e.g. This is not a match. It would have been a match on the previous keystroke:
  # bindingKeystrokes = ['ctrl-tab', '^tab']
  # userKeystrokes    = ['ctrl-tab', '^tab', '^ctrl']
  return false if userKeystrokeIndex < userKeystrokes.length - 1

  if isPartialMatch and bindingRemainderContainsOnlyKeyups
    MATCH_TYPES.KEYDOWN_EXACT
  else if isPartialMatch
    MATCH_TYPES.PARTIAL
  else
    MATCH_TYPES.EXACT
