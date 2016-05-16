FROM test 

RUN chmod 744 /home/user/.ssh/authorized_keys
RUN chown user /home/user/.ssh/authorized_keys
ADD files/.bashrc /home/user/.bashrc
ADD files/test /home/user/test
RUN chmod 755 /home/user/test
env PATH /usr/lib64/openmpi/bin:$PATH

CMD ["/usr/sbin/sshd", "-D", "-d"]
