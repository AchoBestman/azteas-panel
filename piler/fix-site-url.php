<?php
// Corrige SITE_URL dans config-site.php pour pointer vers la bonne URL finale.
// Remplacement INCONDITIONNEL via regex : peu importe la valeur actuelle
// (defaut d'origine, ancien port de test, etc.), elle est toujours ecrasee
// par la valeur correcte. Rend ce correctif veritablement idempotent.
//
// La nouvelle valeur est lue depuis la variable d'environnement NEW_SITE_URL,
// passee par fix-piler-config.sh au moment de l'execution.

$file = '/etc/piler/config-site.php';
$content = file_get_contents($file);

$newUrl = getenv('NEW_SITE_URL');
$new = "\$config['SITE_URL'] = '" . $newUrl . "';";

// Regex : matche n'importe quelle valeur actuelle de SITE_URL, sur une seule ligne
$pattern = '/\$config\[\'SITE_URL\'\]\s*=\s*.*?;/';

if (preg_match($pattern, $content)) {
    $content = preg_replace($pattern, $new, $content, 1);
    file_put_contents($file, $content);
    echo "SITE_URL corrige vers: $newUrl\n";
} else {
    // Ligne absente (cas rare) : on l'ajoute a la fin du fichier
    file_put_contents($file, $content . "\n" . $new . "\n");
    echo "SITE_URL absent, ajoute: $newUrl\n";
}
