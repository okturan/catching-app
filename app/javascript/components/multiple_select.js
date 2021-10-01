import MultipleSelect from 'multiple-select-js'

const initMultipleSelect = () => {
  new MultipleSelect('#user-list', {
    placeholder: ''
    })
}

export { initMultipleSelect }
