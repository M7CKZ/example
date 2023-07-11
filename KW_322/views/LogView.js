import { lcl } from '../other/Localization'
import { Model } from '../models/Model'

export const LogView = {
  Model,
  ctx: 'Log',
  lcl: lcl.log_view,
  add:() => LogView,

  TABLE_CHECKBOX_CHECKED: '<div class="webix_table_checkbox checked cursor-auto"></div>',
  TABLE_CHECKBOX_NOTCHECKED: '<div class="webix_table_checkbox notchecked cursor-auto"></div>',

  render() {
    this.localId = ComponentManager.bind_localId(this)

    objUI_dialogs.render_dialog_window({
      id: this.id = objUtils.uid(),
      height: 600, 
      width: 1200,
      head: objUI.window_head({ win_id: this.id, caption: this.lcl.header }),
      body: {
        rows: [
          objUI.toolbar_horizontal([
            objUI.date_range_picker({...this.localId('date'), label: this.lcl.period, value: {start: new Date(), end: new Date()}}),
            objUI.multicombo({
              ...this.localId('params'), 
              label: this.lcl.params, 
              kw_save_state: true, 
              tagTemplateWord: this.lcl.param, 
              width: 300, 
              value: '1,2', 
              suggest: { selectAll: true, data: [{ id: 1, value: this.lcl.using },{ id: 2, value: this.lcl.priority }]}
            }),
            objUI.icon_btn_refresh({...this.localId('refresh')}),
            {}
          ]),
          objUI.datatable({
            ...this.localId('table'),
            width: 1200,
            columns: [
              objUI.table_column({id: 'tov_name', fillspace: true, header: this.lcl.tov_name}),
              objUI.table_column({id: 'fabr_name', ajust: true, header: this.lcl.fabr_name}),
              objUI.table_column({ id: 'action', adjust: true, header: [{text: this.lcl.action, colspan: 3}, {text:  this.lcl.type}]}),
              objUI.table_column({id: 'old_value', adjust: true, header: [{}, this.lcl.old_value], css: {'text-align': 'center'}, template: "{common.rcheckbox()}"}),
              objUI.table_column({id: 'new_value', adjust: true, header: [{}, this.lcl.new_value], css: {'text-align': 'center'}, template: "{common.rcheckbox()}"}),
              objUI.table_column_datetime({id: 'change_date', adjust: true, header: this.lcl.change_date}),
              objUI.table_column({id: 'person_name', adjust: true, header: this.lcl.person_name})
            ],
            type:{
              rcheckbox:(obj, common, value, config) => [this.lcl.using].includes(obj.action) ? 
                +obj[config.id] === 1 ? this.TABLE_CHECKBOX_CHECKED : this.TABLE_CHECKBOX_NOTCHECKED : obj[config.id]
            },
            on: {
              onCheck(r, c, v, i = this.getItem(r)) { 
                this.blockEvent()
                 (i[c] = !v) && this.updateItem(r, i)
                this.unblockEvent() 
              }
            }
          }),
          objUI.toolbar_horizontal([
            objUI.search_field({
              ...this.localId('search'),
              func: Model.load_logs
            })
          ])
        ]
      }
    })
  },

  init() {
    objUI.extend_with_local_id_on_destination(this, this.root = $$(this.id))
    ComponentManager.save_localId(this)

    Model[this.ctx]['window'] = this.root
    webix.extend(Model[this.ctx]['window'], webix.ProgressBar)

    Model.events.ON_AFTER_LOAD_LOGS.subscribe((result) => {
      Model.Log.table.define_default(result[0]) 
      Model.Log.window.hideProgress()
    })

    Model.Log.refresh.attachEvent('onItemClick', () => Model.load_logs())
  }
}