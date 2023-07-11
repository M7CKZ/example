import { lcl } from '../other/Localization'
import { Model } from '../models/Model'

export const MidController = {

  //Запуск контроллера
  listen() {
    Model.events.ON_AFTER_LOAD_PRODUCTS.subscribe((result) => this.products_loaded(result))
    Model.events.UPDATE_PRIORITY.subscribe(this.update_priority)
    Model.Mid.table.attachEvent('onItemClick', this.onClick)
  },

  //Обновление приоритета
  update_priority(priority = lcl.mid_view.no) {
    Model.Priority.table.data.each((item) => +item.use > 0 && (priority = lcl.mid_view.yes))
    Model.get_current_product().priority = priority
    Model.Mid.table.updateItem(Model.get_current_product().id)
  },

  //Загрузка товаров
  load_products() {
    Model.set_data_request(Model.Mid.table.get_request_param())
    Model.load_products().then()
  },

  //Открываем приоритеты
  onClick(_, e) { e.target.classList.contains('priority') && Model.load_fabr() },

  //Проверка на возможность загрузить еще данные (//TODO куда то пропало использование, вернуть)
  possibility: () => Model.get_total() !== Model.Mid.table.count(),

  //Товары загружены
  products_loaded(result) {
    Model.set_total(+result[1][0].total)
    Model.set_current_user(result[2][0].fio)

    Model.Mid.table.append_default(Model.get_total(), result[0])
    Model.Bot.counter.setValue(Model.get_total())
    Model.root.hideProgress()
    
    if(Model.get_income_params()?.drugId || Model.get_income_params()?.drug_id) Model.Mid.table.select_first() && Model.load_fabr()
  },

}