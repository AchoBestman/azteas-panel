<?php


class ControllerLoginLogout extends Controller {
   private $error = array();

   public function index(){

      $this->id = "content";
      $this->template = "login/logout.tpl";
      $this->layout = "common/layout-empty";

      $request = Registry::get('request');
      $session = Registry::get('session');

      $this->load->model('user/auth');

      $this->data['title'] = $this->data['text_logout'];
      $this->data['title_prefix'] = TITLE_PREFIX;

      if(ENABLE_SAAS == 1) {
         $this->load->model('saas/customer');
         $this->model_saas_customer->offline($session->get('email'));
      }

      logout();

      // Azteas : redirection immediate vers le formulaire de connexion,
      // plutot que d'afficher la page "vous avez ete deconnecte, cliquez ici
      // pour vous reconnecter" par defaut de Piler ($this->render() ci-dessus,
      // desormais inutile puisqu'on ne rend plus login/logout.tpl).
      header('Location: ' . PATH_PREFIX);
      exit();
   }


}
