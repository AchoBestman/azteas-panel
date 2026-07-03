<div id="messagelistcontainer" class="pane-upper-content">

<?php if(FULL_GUI) { ?>
  <div class="mail-list-toolbar">
    <input type="checkbox" id="bulkcheck" name="bulkcheck" value="1" <?php if(SEARCH_RESULT_CHECKBOX_CHECKED == 1) { ?>checked="checked"<?php } ?> class="restorebox" onclick="Piler.toggle_bulk_check('');" />
    <span class="mail-list-toolbar-label">Select all</span>
  </div>
<?php } ?>

  <!-- Piler.fill_current_messages_array() (piler.js) exige explicitement des
       <tr id="e_..."> a l'interieur de "#results tbody" (verifie
       x.nodeName == "TR") pour construire Piler.Messages ; sans ca, cliquer
       sur un message envoie un id "undefined" au serveur ("invalid id").
       On garde donc table/tbody/tr/td et on habille tout en liste via CSS
       (mail-list-* dans azteas-panes.css), pas en changeant les balises. -->
  <table id="results" class="mail-list">
    <tbody>

<?php $i=0; foreach ($messages as $message) { ?>

    <!-- Piler.view_message_by_pos() remplace tout l'attribut class de cette
         ligne par "resultrow" / "resultrow highlighted" (attr('class', ...),
         pas addClass()) : le style doit donc s'appuyer sur .resultrow, qui
         seul survit a la selection, pas sur une classe personnalisee ici. -->
    <tr class="resultrow new <?php if($message['deleted'] == 1) { ?>xxx<?php } ?>" id="e_<?php print $message['id']; ?>" onmouseover="Piler.current_message_id = <?php print $message['id']; ?>; return false;" onclick="Piler.view_message_by_pos(<?php print $i; ?>);">

<?php if(FULL_GUI) { ?>
      <td class="mail-list-item-select" onclick="Piler.stop_propagation(event);">
        <input type="checkbox" id="r_<?php print $message['id']; ?>" name="r_<?php print $message['id']; ?>" value="iiii" <?php if(SEARCH_RESULT_CHECKBOX_CHECKED == 1) { ?>checked="checked"<?php } ?> class="restorebox" />
      </td>
<?php } ?>

      <td class="mail-list-item-body">
        <div class="mail-list-item-header">
          <span class="mail-list-from"><strong><?php print $text_from; ?>:</strong> <?php print $message['from']; ?></span>
          <span class="mail-list-date" title="<?php print $message['preview_date']; ?>"><?php print $message['date']; ?></span>
        </div>
        <div class="mail-list-to"><strong><?php print $text_to; ?>:</strong> <?php print implode(', ', $message['to']); ?></div>
        <div class="mail-list-subject-row">
          <a href="#" class="mail-list-subject <?php if($message['deleted'] == 1) { ?>xxx<?php } ?>"><?php print $message['subject']; ?></a>
<?php if(ENABLE_REFERENCES == 1 && $message['reference']) { ?>
          <a href="#" class="mail-list-conversation-link <?php if($message['deleted'] == 1) { ?>xxx<?php } ?>" title="<?php print $text_conversation_available; ?>" onclick="$('#ref').val('<?php print $message['reference']; ?>'); Piler.expert(this); Piler.stop_propagation(event);">[+]</a>
<?php } ?>
<?php if($message['private'] == 1) { ?> <i class="bi bi-incognito private" title="private"></i><?php } ?>
<?php if($message['marked_for_removal'] == 1) { ?> <span class="private">R</span><?php } ?>
          <span class="mail-list-size">: <?php print $message['size']; ?></span>
        </div>
      </td>

      <td class="mail-list-item-flags">
<?php if($message['spam'] == 1) { ?><i class="bi bi-exclamation-triangle spam" title="<?php print $text_spam_flag; ?>"></i><?php } ?>
<?php if($message['attachments'] > 0) { ?><i class="bi bi-paperclip attachment" title="<?php print $text_attachment_flag; ?>"></i><?php } ?>
<?php if($message['note']) { ?><i class="bi bi-sticky notes" title="<?php print $message['note']; ?>"></i><?php } ?>
<?php if($message['tag']) { ?><i class="bi bi-tag tag" title="<?php print $message['tag']; ?>"></i><?php } ?>
      </td>

    </tr>

<?php $i++; } ?>

    </tbody>
  </table>

</div>

<div id="messagelistfooter" class="boxfooter mail-list-footer upper-pane-fixed">

  <div class="mail-list-footer-paging">
<?php if($n > 0) {
       include_once DIR_BASE . 'templates/common/paging.tpl';

       if(FULL_GUI && Registry::get('auditor_user') == 1 && $session->get("sphx_query")) { ?>
         <span class="ms-5"><a href="#" class="mail-list-saved-query-link" onclick="Piler.show_message('messagebox1', '<?php H($session->get("sphx_query")); ?>', 5);">sphinx</a></span>
<?php  }
     } else { ?>
    <span class="text-danger"><?php print $text_none_found; ?></span>
<?php } ?>
  </div>

  <div class="mail-list-footer-actions">

    <input type="hidden" id="tag_keys" name="tag_keys" value="<?php print $all_ids; ?>" />
    <input type="hidden" id="_ref" name="_ref" value="<?php if(isset($_ref)) { print $_ref; } ?>" />

    <span class="mail-list-footer-actions-label"><?php print $text_with_selected; ?>:</span>

<?php if(SMARTHOST || ENABLE_IMAP_AUTH == 1) {
        if(isAuditorUser() == 1) { ?>
      <a href="#" class="btn btn-link" data-bs-toggle="modal" data-bs-target="#bulkRestoreModal" title="<?php print $text_bulk_restore_selected_emails; ?>"><i class="bi bi-send"></i></a>
<?php   } else { ?>
      <a href="#" class="btn btn-link" onclick="Piler.bulk_restore_messages('<?php print $text_restored; ?>', '');" title="<?php print $text_bulk_restore_selected_emails; ?>"><i class="bi bi-send"></i></a>
<?php   }
      } ?>

    <a href="#" class="btn btn-link" onclick="Piler.download_messages();" title="<?php print $text_bulk_download; ?>"><i class="bi bi-download"></i></a>

<?php if(ENABLE_DELETE == 1 && isAuditorUser() == 1) { ?>
      <a href="#" class="btn btn-link" data-bs-toggle="modal" data-bs-target="#deleteModal" title="<?php print $text_remove; ?>"><i class="bi bi-trash text-danger"></i></a>
<?php } ?>

    <!-- Ce n'est pas un champ de recherche : Piler.tag_search_results() applique
         ce texte comme tag aux messages actuellement COCHES (get_selected_messages_list()) ;
         sans case cochee, le clic sur l'icone Tag ne fait rien (silencieusement). -->
    <input type="text" id="tag_value" name="tag_value" class="tagtext" placeholder="Nom du tag..." />
    <a href="#" class="btn btn-link" onclick="Piler.tag_search_results('<?php print $text_tagged; ?>');" title="<?php print $text_tag_selected_messages; ?>"><i class="bi bi-tags tag" title="Tag"></i></a>

  </div>

</div>
