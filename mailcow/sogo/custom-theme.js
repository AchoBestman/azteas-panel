// Azteas branding for SOGo (Angular Material theming).
// Palette derived from the Azteas primary brand color #140066.
angular.module('SOGo.Common').config(['$mdThemingProvider', function ($mdThemingProvider) {

  $mdThemingProvider.definePalette('azteas', {
    '50': 'E3E0ED',
    '100': 'B9B3D1',
    '200': '8A80B3',
    '300': '5B4D94',
    '400': '37267D',
    '500': '140066',
    '600': '12005C',
    '700': '100052',
    '800': '0E0047',
    '900': '0C003D',
    'A100': '5B4D94',
    'A200': '37267D',
    'A400': '140066',
    'A700': '100052',
    'contrastDefaultColor': 'light',
    'contrastDarkColors': ['50', '100', '200', '300', 'A100'],
    'contrastLightColors': ['400', '500', '600', '700', '800', '900', 'A200', 'A400', 'A700']
  });

  $mdThemingProvider.theme('default')
    .primaryPalette('azteas', {
      'default': '500',  // barre d'outils du haut
      'hue-1': '400',
      'hue-2': '700',    // barre d'outils de la sidebar
      'hue-3': 'A700'
    })
    .accentPalette('azteas', {
      'default': '600',  // boutons fab, écran de login
      'hue-1': '300',    // barre d'outils de la liste centrale
      'hue-2': '300',    // surlignage des mails sélectionnés
      'hue-3': 'A200'
    })
    .backgroundPalette('grey');

}]);




