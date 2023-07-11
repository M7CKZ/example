import { lcl } from '../other/Localization'
import { Model } from '../models/Model'
import { MidController } from '../controllers/MidController'

export const MidView = {
  Model,
  ctx: 'Mid',
  lcl: lcl.mid_view,
  add:() => MidView,

  render() {
    this.localId = ComponentManager.bind_localId(this)

    return {
      id: this.id = objUtils.uid(),
      rows: [
        {
          view: 'kw_srvdatatable',
          ...this.localId('table'),
          sort_col: 'name',
          sort_dir: 'asc',
          data_request: MidController.load_products,
          columns: [
            objUI.table_column({ id: 'name', adjust: true, header: this.lcl.name}),
            objUI.table_column({
              id: 'priority',
              header: this.lcl.priority,
              width: 130,
              minWith: 130,
              template: item => objUI.table_column_icon_template({
                id: 'priority',
                icon: objUI.EDIT_ICON,
                text: item.priority
              })
            }),
            objUI.table_column_datetime({ id: 'change_date', adjust: true, header: this.lcl.change_date})
          ],
          // on: {
          //   onStructureLoad() { this.eachColumn((id) => id !== 'name' && (this.getColumnConfig(id).sort = false)) }
          // }
        }
      ]
    }
  },

  init() {
    objUI.extend_with_local_id_on_destination(this, this.root = $$(this.id))
    ComponentManager.save_localId(this)
    MidController.listen()
  }
}