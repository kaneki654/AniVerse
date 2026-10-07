import 'package:flutter/painting.dart';

/// The AniVerse emblem as pixel art, cell by cell, for the intro animation:
/// assets/icon/aniverse_icon_pixel.png (34x30) read into rows, so every pixel
/// can fly in and land on its own. If that PNG changes, regenerate these rows
/// from it (one character per pixel, '.' for transparent).
class LogoSprite {
  static const rows = [
    '..............A...A...............',
    '.............ABAAACA..............',
    '.............ABBBBCCA.............',
    '............ADDBBBCEA.............',
    '............ADBBBCCECA......AAA...',
    '...........ABBBBBCCCCA...AAADEEAA.',
    '...........ABBBBBCCCCCA.AEEEEEEBBA',
    '..........ABBBBBFECCCCBA.AAAAEEBBA',
    '..........ABBBBEFECCCCBA....AEEBBA',
    '.........ABBBBEEAACCCCBBA...ABBBA.',
    '........ABBBBBEEAACCCBBBA..ABBBBA.',
    '........ABBBBEEAA.ACBBCCBAACCCBA..',
    '.......ABBBBBEEEBAACCCCCBACCCCA...',
    '.......ABBBBEEAEBBAACCCCCCCECA....',
    '......ABBBBBEAAEBBBACCCCCCEEA.....',
    '......ABBBBEEAAEEEA.AECCCEEA......',
    '.....ABBBBEEA..AAAAABBBCEEBA......',
    '...A.ABBBBEEAAAAAABBBBFFEBBBA.....',
    '..ABABBBBEEEEEEBBBBBFFFFCBBBA.....',
    '.ABBBBBBBEEEEBBBBEEFFFFCCBBBDA....',
    '.ABEBBBBEEBBBBBFFFEEEEEEBBBBDA....',
    'ABBEEECBBBBBBAAAAAAAAAEEBBBBBDA...',
    '.ABBBBCCFFFAA.........AFFBBBBDA...',
    '.ACEEEEEFFA............AFFBBBBBA..',
    '.ACCCCCEEA.............AFFBBBBBA..',
    'ACCCCCEEA...............AEBBBBBBA.',
    '.ACCCCEA................AEEBBBBA..',
    '..AACCA..................AEEEAA...',
    '....AA....................AEA.....',
    '...........................A......',
  ];

  /// The emblem's own colours: it stays crimson whatever palette the app uses,
  /// like the launcher icon.
  static const palette = {
    'A': Color(0xFF050305), // outline
    'B': Color(0xFFE50914), // crimson
    'C': Color(0xFFB80816), // shade
    'D': Color(0xFFFF5A64), // highlight
    'E': Color(0xFF7A0410), // deep shade
    'F': Color(0xFF3D0107), // darkest
  };

  static int get width => rows.first.length;
  static int get height => rows.length;

  /// Every painted cell: (x, y, colour key).
  static List<(int, int, String)> cells() => [
        for (var y = 0; y < rows.length; y++)
          for (var x = 0; x < rows[y].length; x++)
            if (rows[y][x] != '.') (x, y, rows[y][x]),
      ];
}
