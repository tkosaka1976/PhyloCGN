require 'csv'

input_fn = ARGV.shift
t_col = ARGV.shift
out_fn = ARGV.shift 

csv = CSV.read(input_fn, headers:true)
File.open(out_fn, "w") { it.puts csv[t_col] }

