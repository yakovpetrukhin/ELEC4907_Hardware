# -*- coding: utf-8 -*-
"""
Created on Thu Mar  9 13:28:34 2023

@author: yakovpetrukhin
"""

from fpga import FPGA, eval_outputs, start_temp_fpga_writer, start_cts_monitor, start_fpga_nn_iterator
from pipe import start_pipes
from command_handler import start_command_packager, start_command_packager_v2
import logging
from collections import deque
import time
import threading
import cProfile
import pstats

shutdown = threading.Event()


def main():
    format = "%(asctime)s: %(message)s"
    logging.basicConfig(format=format, level=logging.DEBUG, datefmt="%H:%M:%S")
                    
    fpga = FPGA('COM3', 576000, exitOnFail = True)
    
    engine_return_queue = deque([])
    instruction_queue = deque([])
    tx_cmd_queue = deque([])
    
    # logging.disable(logging.CRITICAL)
    
    start_pipes(instruction_queue, engine_return_queue)
    
    start_command_packager_v2(instruction_queue, tx_cmd_queue)
    
    start_fpga_nn_iterator(fpga, tx_cmd_queue, engine_return_queue)
    
    
        
    #start_temp_fpga_writer(fpga, tx_cmd_queue)
    


    # with cProfile.Profile() as pr:
    #     fpga.write_data(tx_cmd_queue)
    
    # stats = pstats.Stats(pr)
    # stats.sort_stats(pstats.SortKey.TIME)
    # stats.print_stats()
    # stats.dump_stats(filename='needs_profiling.prof')
    

  

if __name__ == "__main__":
    
    with cProfile.Profile() as pr:
        main()
    
    stats = pstats.Stats(pr)
    stats.sort_stats(pstats.SortKey.TIME)
    stats.print_stats()
    stats.dump_stats(filename='needs_profiling.prof')
    

    
    
    
    