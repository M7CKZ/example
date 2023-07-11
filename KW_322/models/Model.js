import { Provider } from '../providers/Provider'

export const Model = {

  //События
  events: {
    //После загрузки товаров
    ON_AFTER_LOAD_PRODUCTS: new ApplicationEvent(),
    //После загрузки приоритетов
    ON_AFTER_LOAD_FABR: new ApplicationEvent(),
    //После обновления приоритетов
    UPDATE_PRIORITY: new ApplicationEvent(),
    //После загрузки логов
    ON_AFTER_LOAD_LOGS: new ApplicationEvent()
  },

  //Данные для порционного запроса
  data_request: {
    page: 0,
    portion_size: 200,
    sort_col: 'name',
    sort_dir: 'asc',
    total: 0
  },

  //Переданные параметры в модуль
  before_render: undefined,

  //Текущий пользователь
  current_user: '',

  //Текущий товар
  current_product: '',

  // Загрузка товаров
  async load_products() {
    // todo try catch finally
    Model.root.showProgress()
    Model.events.ON_AFTER_LOAD_PRODUCTS.notify(await Provider.load_products(Model.products_param()))
  },

  //Загрузка приоритетов
  async load_fabr() {
    // todo try catch finally
    Model.root.showProgress()
    this.set_income_params(undefined)
    this.set_current_product(this.Mid.table.getSelectedItem())
    Model.events.ON_AFTER_LOAD_FABR.notify(await Provider.load_fabr(Model.Mid.table.getSelectedItem()))
  },

  //Загрузка логов
  async load_logs() {
    // todo try catch finally
    Model.Log.window.showProgress()
    Model.events.ON_AFTER_LOAD_LOGS.notify(await Provider.load_logs(Model.logs_param()))
  },

  //Сохранение приоритета
  save_fabr_priority: async (param) => await Provider.save_fabr_priority(param),

  //Сохранение признака использования
  save_fabr_using: async (param) => await Provider.save_fabr_using(param),

  //Поиск по товару
  search_products:() => Model.Mid.table.request_new_data(),

  //Параметры для логов
  logs_param:() => ({
    date_start: Model.Log.date.get_date_begin_format(),
    date_end: Model.Log.date.get_date_end_format(),
    search: Model.Log.search.getValue(),//Model.get_search_str(Model.Log.search.getValue()),
    search_fabr: Model.Log.search.getValue().split(' ').filter((i) => i !== ''),
    params: Model.Log.params.getValue().split(',')
  }),

  //Параметры для товаров
  products_param:() => ({
    ...Model.get_data_request(),
    ...Model.get_income_params(),
    source: Model.Top.source.getValue(),
    search_name: Model.get_search_str(Model.Bot.search_name.getValue()),
    search_fabr: Model.Bot.search_fabr.getValue()
  }),

  //Поисковая строка
  get_search_str:(v) => v.split(' ').filter((i) => i !== ''),

  //Сеттер общего кол-ва товаров
  set_total:(total) => Model.data_request.total = total,

  //Геттер
  get_total:() => Model.data_request.total,

  //Сеттер текущей порции
  set_page:(page) => Model.data_request.page = page,

  //Геттер
  get_page:() => Model.data_request.page,

  //Сеттер текущего пользователя
  set_current_user:(user_name) => Model.current_user = user_name,

  //Геттер
  get_current_user:() => Model.current_user,

  //Сеттер текущего товара
  set_current_product:(product) => Model.current_product = product,

  //Геттер
  get_current_product:() => Model.current_product,

  //Сеттер данных для порционного расчета
  set_data_request:(data) => Model.data_request = data,

  //Геттер
  get_data_request:() => Model.data_request,

  //Установка входящих параметров в модуль
  set_income_params:(params) => Model.before_render = params,

  //Геттер
  get_income_params:() => Model.before_render,

  //Сортировка
  set_sort:(col, dir) => [Model.data_request.sort_col, Model.data_request.sort_dir] = [col, dir]
}