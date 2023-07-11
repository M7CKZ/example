import { lcl } from '../other/Localization'
import { Model } from '../models/Model'
import { PriorityController } from '../controllers/PriorityController'

export const PriorityView = {
  Model,
  ctx: 'Priority',
  lcl: lcl.priority_view,
  add:() => PriorityView,

  render() {
    this.localId = ComponentManager.bind_localId(this)

    objUI_dialogs.render_dialog_window({
      id: this.id = objUtils.uid(),
      height: 300,
      width: 900,
      head: objUI.window_head({ win_id: this.id, caption: this.lcl.accept }),
      body: {
        rows: [
          objUI.datatable({
            ...this.localId('table'),
            width: 900,
            columns: [
              objUI.table_column({id: 'fabr', adjust: true, header: this.lcl.fabr}),
              objUI.table_column_checkbox({id: 'use', header: {text: this.lcl.use, content: 'KW_headerCheck', func: PriorityController.check}, width: 150}),
              objUI.table_column({ id: 'priority', width: 150, header: this.lcl.priority, editor: 'combo', collection: [{}]}),
              objUI.table_column_datetime({id: 'change_date', adjust: true, header: this.lcl.change_date}),
              objUI.table_column({id: 'fio', fillspace: true, header: this.lcl.fio})
            ]
          })
        ]
      }
    })
  },

  init() {
    objUI.extend_with_local_id_on_destination(this, this.root = $$(this.id))
    ComponentManager.save_localId(this)
    PriorityController.listen()
    
    Model[this.ctx]['window'] = this.root
    Model[this.ctx]['header'] = $$(this.id + '_head_lbl')
  }
}