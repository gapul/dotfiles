// Shared by the Rosé Pine canvas wallpapers. The object is mutated before the
// wallpaper's own constants are derived, then the page is reloaded on an OS
// appearance change so all cached RGB values are rebuilt consistently.
window.followSystemTheme = function (palette) {
  const dark = { ...palette };
  const light = {
    base: '250,244,237',
    surface: '255,250,243',
    overlay: '242,233,225',
    muted: '152,147,165',
    subtle: '121,117,147',
    text: '87,82,121',
    love: '180,99,122',
    gold: '234,157,52',
    rose: '215,130,126',
    pine: '40,105,131',
    foam: '86,148,159',
    iris: '144,122,169',
  };
  const media = matchMedia('(prefers-color-scheme: light)');
  Object.assign(palette, media.matches ? light : dark);
  document.documentElement.style.background = `rgb(${palette.base})`;
  document.body.style.background = `rgb(${palette.base})`;
  media.addEventListener('change', () => location.reload());
};
