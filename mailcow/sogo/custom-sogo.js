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

// CKEDITOR n'existe que sur les pages où l'éditeur de mail est chargé (pas sur
// la page de connexion, ni Calendrier/Contacts/Préférences) : un appel non
// protégé lève une ReferenceError qui interrompt tout le reste de ce script
// sur ces pages-là, empêchant les correctifs ci-dessous de s'exécuter là où
// ils sont justement nécessaires.
if (typeof CKEDITOR !== "undefined") {
  // Change the visible font-size in the editor, this does not change the font of a html message by default
  CKEDITOR.addCss("body {font-size: 16px !important}");

  // Enable scayt by default
  //CKEDITOR.config.scayt_autoStartup = true;
}

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

// Redirige systématiquement l'écran de connexion SOGo vers celui de Mailcow
// (page brandée "AZTEAS WEBMAIL", sélecteur de langue, dark mode masqué...),
// que ce soit à la première visite ou après expiration de session — au lieu
// d'afficher le formulaire de connexion natif de SOGo. Mailcow redirige
// ensuite automatiquement les mailbox users authentifiés vers /SOGo/so/ (cf.
// data/web/index.php de mailcow-dockerized : rôle "user" + sogo_access actif
// => Location: /SOGo/so/, jamais /user), donc pas de conflit avec le blocage
// Traefik de /user.
document.addEventListener("DOMContentLoaded", function () {
  if (document.forms.namedItem("loginForm")) {
    window.location.href = "/";
  }
});
