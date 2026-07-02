// logout function
function mc_logout() {
    fetch("/", {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded"
        },
        body: "logout=1"
    }).then(() => window.location.href = '/');
}

// Custom SOGo JS

// Change the visible font-size in the editor, this does not change the font of a html message by default
CKEDITOR.addCss("body {font-size: 16px !important}");

// Enable scayt by default
//CKEDITOR.config.scayt_autoStartup = true;

// Masque le bouton "mailcow Preferences" (icône "build") injecté par mailcow
// dans les préférences SOGo, qui pointe en dur vers /user — or /user est
// bloqué (403) par la règle Traefik mailcow-block-user, volontairement,
// pour que les mailbox users ne passent que par le webmail SOGo. Ciblé par
// href seul (élément sans identifiant propre) : pas d'aria-label, qui est
// traduit selon la langue de l'utilisateur.
(function () {
  var style = document.createElement("style");
  style.textContent = 'a[href="/user"] { display: none !important; }';
  document.head.appendChild(style);
})();

// Fait correspondre la langue de l'écran de connexion SOGo à celle choisie
// sur l'écran de connexion Mailcow (cookie "mailcow_locale").
// Ne s'applique que si le formulaire de connexion SOGo est affiché (pas de
// session active) — même détection que l'ancien redirect vers /user retiré
// plus haut — pour ne jamais écraser la préférence de langue qu'un
// utilisateur a déjà choisie dans ses propres préférences SOGo.
// SOGo attend un nom complet ("French", "German", ...) correspondant à un de
// ses dossiers .lproj, pas un code ISO. Table vérifiée à partir du dropdown
// réel de Mailcow (clés xx-yy, ex. "pt-br") et de la liste réelle des
// <md-option value="..."> de SOGo. Repli sur le préfixe 2 lettres seul (clés
// xx) si le cookie ne conserve pas la variante régionale — avec un choix par
// défaut pour les langues ambiguës (pt -> Portugal, zh -> Chine). uz/vi
// n'ont pas d'équivalent SOGo et sont donc absents (aucune redirection).
// sessionStorage évite une boucle si changeLanguage ne renvoie pas vers une
// URL contenant "language=" (cas normal où SOGo relit son propre choix).
document.addEventListener("DOMContentLoaded", function () {
  if (!document.forms.namedItem("loginForm")) return;
  if (/\blanguage=/.test(window.location.search)) return;
  if (sessionStorage.getItem("azteasSogoLangSynced")) return;

  var match = document.cookie.match(/(?:^|;\s*)mailcow_locale=([a-z]{2}(?:-[a-z]{2})?)/);
  if (!match) return;

  var SOGO_LANGUAGES = {
    "bg-bg": "Bulgarian", "cs-cz": "Czech", "da-dk": "Danish", "de-de": "German",
    "en-gb": "English", "es-es": "SpanishSpain", "fi-fi": "Finnish", "fr-fr": "French",
    "gr-gr": "Greek", "hu-hu": "Hungarian", "it-it": "Italian", "ja-jp": "Japanese",
    "ko-kr": "Korean", "lv-lv": "Latvian", "lt-lt": "Lithuanian", "nb-no": "NorwegianBokmal",
    "nl-nl": "Dutch", "pl-pl": "Polish", "pt-br": "BrazilianPortuguese", "pt-pt": "Portuguese",
    "ro-ro": "Romanian", "ru-ru": "Russian", "si-si": "Slovenian", "sk-sk": "Slovak",
    "sv-se": "Swedish", "tr-tr": "TurkishTurkey", "uk-ua": "Ukrainian",
    "zh-cn": "ChineseChina", "zh-tw": "ChineseTaiwan",

    bg: "Bulgarian", cs: "Czech", da: "Danish", de: "German", en: "English",
    es: "SpanishSpain", fi: "Finnish", fr: "French", gr: "Greek", hu: "Hungarian",
    it: "Italian", ja: "Japanese", ko: "Korean", lv: "Latvian", lt: "Lithuanian",
    nb: "NorwegianBokmal", nl: "Dutch", pl: "Polish", pt: "Portuguese",
    ro: "Romanian", ru: "Russian", si: "Slovenian", sk: "Slovak", sv: "Swedish",
    tr: "TurkishTurkey", uk: "Ukrainian", zh: "ChineseChina"
  };
  var sogoLanguage = SOGO_LANGUAGES[match[1]];
  if (sogoLanguage && typeof ApplicationBaseURL !== "undefined") {
    sessionStorage.setItem("azteasSogoLangSynced", "1");
    window.location.href = ApplicationBaseURL + "changeLanguage?language=" + sogoLanguage;
  }
});
