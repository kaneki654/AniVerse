import 'pixel.dart';

/// Every icon in the 2D UI, drawn as pixel art. 'X' pixels take the colour the
/// icon is drawn in; other letters are fixed palette colours (see [Px.keys]).
class Sprites {
  static const play = Sprite([
    'XX.......',
    'XXXX.....',
    'XXXXXX...',
    'XXXXXXXX.',
    'XXXXXXXXX',
    'XXXXXXXX.',
    'XXXXXX...',
    'XXXX.....',
    'XX.......',
  ]);

  static const pause = Sprite([
    'XXX...XXX',
    'XXX...XXX',
    'XXX...XXX',
    'XXX...XXX',
    'XXX...XXX',
    'XXX...XXX',
    'XXX...XXX',
    'XXX...XXX',
    'XXX...XXX',
  ]);

  static const back = Sprite([
    '....X....',
    '...XX....',
    '..XXX....',
    '.XXXXXXXX',
    'XXXXXXXXX',
    '.XXXXXXXX',
    '..XXX....',
    '...XX....',
    '....X....',
  ]);

  static const chevron = Sprite([
    'XX.....',
    'XXX....',
    '.XXX...',
    '..XXX..',
    '...XXX.',
    '..XXX..',
    '.XXX...',
    'XXX....',
    'XX.....',
  ]);

  static const rewind = Sprite([
    '...X...X',
    '..XX..XX',
    '.XXX.XXX',
    'XXXXXXXX',
    '.XXX.XXX',
    '..XX..XX',
    '...X...X',
  ]);

  static const forward = Sprite([
    'X...X...',
    'XX..XX..',
    'XXX.XXX.',
    'XXXXXXXX',
    'XXX.XXX.',
    'XX..XX..',
    'X...X...',
  ]);

  static const skipNext = Sprite([
    'X......XX',
    'XXX....XX',
    'XXXXX..XX',
    'XXXXXXXXX',
    'XXXXX..XX',
    'XXX....XX',
    'X......XX',
  ]);

  static const search = Sprite([
    '..XXXX....',
    '.XX..XX...',
    'XX....XX..',
    'XX....XX..',
    'XX....XX..',
    '.XX..XX...',
    '..XXXXXX..',
    '......XXX.',
    '.......XXX',
    '........XX',
  ]);

  static const gear = Sprite([
    '....XXX....',
    '.XX.XXX.XX.',
    '.XXXXXXXXX.',
    '..XXXXXXX..',
    'XXXX...XXXX',
    'XXXX...XXXX',
    'XXXX...XXXX',
    '..XXXXXXX..',
    '.XXXXXXXXX.',
    '.XX.XXX.XX.',
    '....XXX....',
  ]);

  static const user = Sprite([
    '...XXX...',
    '..XXXXX..',
    '..XXXXX..',
    '..XXXXX..',
    '...XXX...',
    '.........',
    '.XXXXXXX.',
    'XXXXXXXXX',
    'XXXXXXXXX',
  ]);

  static const grid = Sprite([
    'XXXX.XXXX',
    'XXXX.XXXX',
    'XXXX.XXXX',
    'XXXX.XXXX',
    '.........',
    'XXXX.XXXX',
    'XXXX.XXXX',
    'XXXX.XXXX',
    'XXXX.XXXX',
  ]);

  static const clock = Sprite([
    '...XXXXX...',
    '..X.....X..',
    '.X...X...X.',
    'X....X....X',
    'X....X....X',
    'X....XXX..X',
    'X.........X',
    'X.........X',
    '.X.......X.',
    '..X.....X..',
    '...XXXXX...',
  ]);

  static const trash = Sprite([
    '...XXX...',
    'XXXXXXXXX',
    '.........',
    '.XXXXXXX.',
    '.X.X.X.X.',
    '.X.X.X.X.',
    '.X.X.X.X.',
    '.X.X.X.X.',
    '.XXXXXXX.',
  ]);

  static const fullscreen = Sprite([
    'XXX...XXX',
    'X.......X',
    'X.......X',
    '.........',
    '.........',
    '.........',
    'X.......X',
    'X.......X',
    'XXX...XXX',
  ]);

  static const fullscreenExit = Sprite([
    '..X...X..',
    '..X...X..',
    'XXX...XXX',
    '.........',
    '.........',
    '.........',
    'XXX...XXX',
    '..X...X..',
    '..X...X..',
  ]);

  static const swap = Sprite([
    '......X..',
    '......XX.',
    'XXXXXXXXX',
    '......XX.',
    '..XX..X..',
    '.XX......',
    'XXXXXXXXX',
    '.XX......',
    '..X......',
  ]);

  static const refresh = Sprite([
    '..XXXX.X.',
    '.XX..XXX.',
    'XX...XXX.',
    'X........',
    'X.......X',
    'XX.....XX',
    '.XX...XX.',
    '..XXXXX..',
  ]);

  static const check = Sprite([
    '........X',
    '.......XX',
    '......XX.',
    'X....XX..',
    'XX..XX...',
    '.XXXX....',
    '..XX.....',
  ]);

  static const close = Sprite([
    'XX...XX',
    'XXX.XXX',
    '.XXXXX.',
    '..XXX..',
    '.XXXXX.',
    'XXX.XXX',
    'XX...XX',
  ]);

  static const eye = Sprite([
    '...XXXXX...',
    '.XX.....XX.',
    'X....X....X',
    'X...XXX...X',
    'X....X....X',
    '.XX.....XX.',
    '...XXXXX...',
  ]);

  static const eyeOff = Sprite([
    'X..XXXXX...',
    '.XX.....XX.',
    'X.X..X....X',
    'X...XXX...X',
    'X....XXX..X',
    '.XX.....XX.',
    '...XXXXX.X.',
  ]);

  static const lock = Sprite([
    '..XXXXX..',
    '.X.....X.',
    '.X.....X.',
    'XXXXXXXXX',
    'XXXX.XXXX',
    'XXX...XXX',
    'XXXX.XXXX',
    'XXXXXXXXX',
    'XXXXXXXXX',
  ]);

  static const logout = Sprite([
    'XXXXX....',
    'X...X....',
    'X...X.X..',
    'X...X.XX.',
    'X.XXXXXXX',
    'X...X.XX.',
    'X...X.X..',
    'X...X....',
    'XXXXX....',
  ]);

  static const floppy = Sprite([
    'XXXXXXXX.',
    'X.XXXX.XX',
    'X.XXXX..X',
    'X.......X',
    'X.XXXXX.X',
    'X.X...X.X',
    'X.X...X.X',
    'XXXXXXXXX',
  ]);

  static const star = Sprite([
    '....X....',
    '....X....',
    '...XXX...',
    'XXXXXXXXX',
    '.XXXXXXX.',
    '..XXXXX..',
    '..XX.XX..',
    '.XX...XX.',
    '.X.....X.',
  ]);

  /// Section-header drop: outlined, shaded, with a glint.
  static const bloodDrop = Sprite([
    '...K...',
    '..KRK..',
    '..KRK..',
    '.KRRRK.',
    '.KHRRK.',
    'KRHRRRK',
    'KRRRRrK',
    'KRRRrrK',
    '.KrrrK.',
    '..KKK..',
  ]);

  /// The failure-screen skull, bleeding from the eyes.
  static const skull = Sprite([
    '..KKKKKKK..',
    '.KWWWWWWWK.',
    'KWWWWWWWWWK',
    'KWRRWWWRRWK',
    'KWRRWWWRRWK',
    'KWRWWKWWRWK',
    '.KRWWWWWRK.',
    '..KWKWKWK..',
    '..KWKWKWK..',
    '...KKKKK...',
  ]);

  /// Small marker for an episode already watched.
  static const skullSmall = Sprite([
    '.KKKKK.',
    'KWWWWWK',
    'KRWWWRK',
    'KWWKWWK',
    '.KWKWK.',
    '..KKK..',
  ]);
}
