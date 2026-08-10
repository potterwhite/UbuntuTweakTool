
import sys


print("\n")
print("=====Pin-Map-Calculation-System=====")
print("\n")

argc_num = len(sys.argv)
PINS_OF_GROUP = int(8)
PINS_OF_INTERFACE = int(32)
TOTAL_INTERFACES = int(5)
max_num = int(PINS_OF_INTERFACE * TOTAL_INTERFACES)

def get_group_mapping(number):
	group_mapping = {
		0: 'A',
		1: 'B',
		2: 'C',
		3: 'D',
	}
	return group_mapping.get(number, 'unknown-group')

def format_all(interface, group, pin):
    #string_group = get_group_mapping(group)
	print(f"GPIO{interface}_{get_group_mapping(group)}{pin}")

	#print(f"gpio{interface} RK_P{group}{pin}")
	print("\n")

######


def main():
	if argc_num == 1:
		print("give me the start number please")
	elif argc_num > 2:
		print("one number once")
	else:
		# 1st stage: validation number
		try:
			start_num = int(sys.argv[1])
			#print(f"start_num={start_num}")

		except ValueError:
			print(f"argv[1]({sys.argv[1]}) is illegal number")
			sys.exit(1)

		# 2nd stage: check if start_num greater than max limitor
		if start_num > max_num:
			print(f"number is too big, max is {max_num}")
			sys.exit(1)

		# 3rd stage: calculate interface name
		interface_num = int(start_num / PINS_OF_INTERFACE)
		#print(f"Interface: {interface_num}")

		# 4th stage: calculate group name
		remainder = int(start_num % PINS_OF_INTERFACE)
		group_num = int(remainder / PINS_OF_GROUP)
		#print(f"Group: {get_group_mapping(group_num)}")

		# 5th stage: calculate pins number in group
		pin_num = int(remainder % PINS_OF_GROUP)
		#print(f"Pin: {pin_num}")

		format_all(interface_num, group_num, pin_num)
	#	try:
	#	except Exception as e:
	#		print(f"something wrong: {e}")

if __name__ == "__main__":
	main()
