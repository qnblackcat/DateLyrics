# DateLyrics 🎵
## Apple Music lyrics in the Lock Screen date view!

DateLyrics brings Apple Music lyrics to the lock screen date widget view. Lyrics are pulled directly from Apple Music, which means that word-by-word lyrics (karaoke style syllable highlighting) is also supported when available.

YouTube Music is also supported as an **experimental** option, see [YouTube Music (experimental)](#youtube-music-experimental).

---

<table align="center">
  <tr>
    <td align="center">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="DateLyricsIconDark.png">
        <img src="DateLyricsIconLight.png" width="280" alt="DateLyrics icon" style="border-radius: 18px;">
      </picture>
    </td>
    <td align="center">
      <img src="thumbnail.png" width="380" alt="DateLyrics thumbnail">
    </td>
  </tr>
</table>

---

## YouTube Music (experimental)

Off by default. Turn on **Enable YouTube Music Support** in Settings → DateLyrics → Experimental, then respring. Lyrics come from YouTube Music itself and are fetched automatically for most songs.

- Unofficial and relies on the app's internals, so it may break at any time.
- Tested on YouTube Music v9.41. Newer versions may not work.
- No word highlighting or sweep (even the stock YouTube Music app can't do this).
- Lyrics may drift from the music, most visibly on split lines.
- If lyrics don't appear for a song, open its Lyrics tab once.
- Musixmatch Fallback is not supported.

---

## Compatibility

- DateLyrics supports any **rootless** or **roothide** jailbreak on iOS 16.0 and later.
- Users running semi-jailbreaks such as **NathanLR** will need to inject tweaks into the Music application (and YouTube Music, if used) in order for DateLyrics to work.
- To build the roothide package, use the [roothide fork of Theos](https://github.com/roothide/theos):

```sh

make clean package install FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
make clean package install FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless

```
Download the latest version from my repo: **[Qn_ repo](https://qnblackcat.github.io/repo)**

---

<p align="center">
  <a href="https://github.com/shalamand3r/DateLyrics/releases">
    <img src="https://img.shields.io/github/downloads/shalamand3r/DateLyrics/total?style=plastic&logo=github&label=Downloads&color=ff80bd">
  </a>
</p>
