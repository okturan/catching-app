import MultipleSelect from 'multiple-select-js'

const initMultipleSelect = () => {
  let user = document.querySelector("#user-list")
  if (user) {
    new MultipleSelect('#user-list', {
      placeholder: ''
      })
  }
}

export { initMultipleSelect }
