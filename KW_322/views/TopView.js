import { lcl } from '../other/Localization'
import { Model } from '../models/Model'
import { TopController } from '../controllers/TopController'

export const TopView = {
  Model,
  ctx: 'Top',
  lcl: lcl.top_view,
  add: () => TopView,

  render() {
    this.localId = ComponentManager.bind_localId(this)
    return objUI.toolbar({
      id: this.id = objUtils.uid(),
      cols: [
        objUI.combo({...this.localId('source'), label: this.lcl.source, options: this.source_options(), value: 1, width: 100}),
        objUI.icon_btn_refresh({...this.localId('refresh')}),
        {}
      ]
    })
  },

  init() {
    objUI.extend_with_local_id_on_destination(this, this.root = $$(this.id))
    ComponentManager.save_localId(this)
    TopController.listen()
  },

  source_options:(me = TopView) => [{id: '1', value: me.lcl.all}, {id: '2', value: me.lcl.price}, {id: '3', value: me.lcl.remains}]
}