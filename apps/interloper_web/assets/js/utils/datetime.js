// Date/time utilities
// Less overhead than moment.js

const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function dateFormat (dt) {

  if (typeof dt === 'string' || typeof dt === 'number') {
    dt = new Date(dt);
  }

  function trimpad (val) {
    val = val + '';
    if (val.length > 2) {
      return val.slice(-2);
    }
    if (val.length < 2) {
      return '0' + val;
    }
    return val;
  }

  return days[dt.getDay()] + ', ' +
    trimpad(dt.getDate()) + ' ' + months[dt.getMonth()] + ' ' + dt.getFullYear() + ' ' +
    trimpad(dt.getHours()) + ':' + trimpad(dt.getMinutes()) + ':' + trimpad(dt.getSeconds());
}

export { dateFormat };
