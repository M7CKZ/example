import * as views from './views/Views'
import { lcl } from './other/Localization'
import { Model } from './models/Model'

ModuleManager.define((value = {
  locales: lcl.module_header,
  window_param: { window_maximize: true },
  id: objUtils.uid(),

  //Нажатие на меню, открываемое в левом верхнем углу
  func_main_menu_on_item_click:() => Model.Log.window.show(),

  //Рендер меню в левом верхнем углу
  render_main_menu:() => objWindow.func_add_main_menu(window[ModuleManager.script_name()].win, [{ value: lcl.log }]),

  //Установка параметров пришедших в модуль
  before_render:(param) => Model.set_income_params(param),

  //Рендер интерфейса
  render:(me = value) => ({id: me.id, rows: [views.TopView.render(), views.MidView.render(), views.BotView.render()]}),
  
  //Инициализация
  init() {
    views.LogView.render()
    views.PriorityView.render()
    this.add_progress()
    ComponentManager.init_views(Object.values(views))
  },

  //Вешаем прогресс бар
  add_progress:(me = value) => (Model.root = $$(me.id)) && webix.extend(Model.root, webix.ProgressBar)
}) => value)