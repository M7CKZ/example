import { Model } from '../models/Model'
import { lcl } from '../other/Localization'

export const PriorityController = {
  listen() {
    Model.events.ON_AFTER_LOAD_FABR.subscribe((result => this.fabr_loaded(result)))
    Model.Priority.table.attachEvent('onbeforeeditstop', this.priority_change)
    Model.Priority.table.attachEvent('onCheck', this.autozakaz_use)
  },

  //Изменение опции - использовать в заказе у производителя
  autozakaz_use(row) {
    PriorityController.update(Model.save_fabr_using, Model.Priority.table.getItem(row))
    Model.events.UPDATE_PRIORITY.notify()
  },

  //TODO переделать поочередное обновление товара в цикле через изменения товаров одним массивом
  //Нажатие на галочку в заголовке столбца - KW_headerCheck
  check(value, item) {
    item.table.data.each((obj) => {
      const current = obj[item.columnId]
      if(current !== value && (((!current || +current === 0) && +value === 1) || (+value === 0 && +current === 1 )))  {
        obj[item.columnId] = value
        PriorityController.update(Model.save_fabr_using, obj)
      }
    })
    Model.get_current_product().priority = +value === 0 ? lcl.mid_view.no : lcl.mid_view.yes
    Model.Mid.table.updateItem(Model.get_current_product().id)
  },

  //Обновление данных по товару
  update(func, item, id, param) {
    item.change_date = (new Date()).toString()
    item.fio = Model.current_user
    Model.Priority.table.updateItem(id || item.id)

    Model.get_current_product().change_date = item.change_date
    Model.Mid.table.updateItem(Model.get_current_product().id)

    func(param || item)
  },

  //Изменение приоритета производителя
  priority_change(item, obj) {
    if(item.value === item.old || (item.value === '' && item.old === null)) return

    if(item.value !== item.old) {
      PriorityController.update(
        Model.save_fabr_priority, Model.Priority.table.getItem(obj.row), obj.row, {...Model.Priority.table.getItem(obj.row), priority: item.value}
      )
    }

    if(item.value !== '' && +item.value !== 0) {
      Model.Priority.table.data.each((row) => {
        if(row.id !== obj.row && +row.priority === +item.value) {
          row.priority = ''
          PriorityController.update(Model.save_fabr_priority, row)
        }
      })
    }
  },

  ///Приоритеты загружены
  fabr_loaded(result) {
    PriorityController.set_header()
    Model.Priority.window.show()

    Model.Priority.table.define_default(result[0])
    this.fill_collection(result[0])

    Model.root.hideProgress()
  },

  //Заголовок окна с настройками приоритетов
  set_header:() => Model.Priority.header.setValue(`${lcl.priority_view.accept} - ${Model.Mid.table.getSelectedItem().name}`),

  //Заполнение списка приоритетов, по кол-ву проивзодителей
  fill_collection(data, arr = []) {
    Model.Priority.table.getColumnConfig('priority').collection.clearAll()

    for(let i = 1; i <= data.length; i++) {
      Model.Priority.table.getColumnConfig('priority').collection.add({id: i, value: i})
    }

    Model.Priority.table.refreshColumns()
  }
}