import { lcl } from '../other/Localization'
import { Model } from '../models/Model'

export const BotView = {
  Model,
  ctx: 'Bot',
  lcl: lcl.bot_view,
  add: () => BotView,

  render() {
    this.localId = ComponentManager.bind_localId(this)

    return objUI.toolbar({
      id: this.id = objUtils.uid(),
      cols: [
        objUI.search_field({
          ...this.localId('search_name'),
          placeholder: this.lcl.name,
          func: Model.search_products
        }),
        objUI.search_field({
          ...this.localId('search_fabr'),
          placeholder: this.lcl.fabr,
          func: Model.search_products,
          hidden: false
        }),
        objUI.label({ label:this.lcl.all}),
        objUI.label_bold({ ...this.localId('counter'), width: 100 }),
        {}
      ]
    })
  },

  init() {
    objUI.extend_with_local_id_on_destination(this, this.root = $$(this.id))
    ComponentManager.save_localId(this)
  }
}