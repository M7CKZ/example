export const Provider = {

  //Загрузка списка товаров
  load_products:(param) => objGlobal.func_post_json({param, procName: '322_1_v2'}),

  //Загрузка данных по производителям
  load_fabr:(param) => objGlobal.func_post_json({param, procName: '322_2_v2'}),

  //Сохранение приоритета производителя
  save_fabr_priority:(param) => objGlobal.func_post_json({param, procType: 'wo', procName: '322_3_v2'}),

  //Сохранение использования производителя в автозаказе
  save_fabr_using:(param) => objGlobal.func_post_json({param, procType: 'wo', procName: '322_4_v3'}),

  //Загрузка логов
  load_logs:(param) => objGlobal.func_post_json({param, procType: 'rw', procName: '322_5_v1'})
}