import { Model } from '../models/Model'

export const TopController = {

  listen() {
    setTimeout(() => Model.Mid.table.request_new_data(), 100)
    Model.Top.refresh.attachEvent('onItemClick', () => Model.Mid.table.request_new_data())
  }

}