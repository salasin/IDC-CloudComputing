import re

iterations_arg = 'num-12'
iterations = re.findall('\d+', iterations_arg)[0]
print(iterations)
